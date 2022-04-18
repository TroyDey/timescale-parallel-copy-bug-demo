-- Function for creating a chunk rereplication plan
-- to bring all under replicated chunks back up to 
-- fully replicated.  It will randomly choose source
-- nodes to copy from for each chunk to attempt to
-- distribute the load.
CREATE OR REPLACE FUNCTION get_chunk_repl_restore_plan() 
RETURNS TABLE(chunk_full_name text, src_node_name name, dst_node_name name)
LANGUAGE PLPGSQL
AS
$$
BEGIN
    RETURN QUERY
    WITH chunk_repl_status AS (
        SELECT
            a.ht_full_name,
            a.chunk_full_name,
            a.node_name,
            a.replication_factor,
            COUNT(*) OVER (PARTITION BY a.chunk_full_name) cnt
        FROM (
            SELECT 
                h.hypertable_schema || '.' || h.hypertable_name ht_full_name,
                c.chunk_schema || '.' || c.chunk_name chunk_full_name, 
                unnest(c.data_nodes) node_name,
                h.replication_factor
            FROM timescaledb_information.chunks c 
            JOIN timescaledb_information.hypertables h 
                ON 
                    c.hypertable_schema = h.hypertable_schema
                    AND c.hypertable_name = h.hypertable_name
        ) a
    )
    SELECT DISTINCT ON (chunk_src_dest.chunk_full_name, chunk_src_dest.dst_node_name)
    chunk_src_dest.chunk_full_name,
    chunk_src_dest.src_node_name,
    chunk_src_dest.dst_node_name
    FROM (
        SELECT
            cdn.chunk_full_name,
            cdn.node_name AS src_node_name,
            adn.node_name AS dst_node_name,
            cdn.replication_factor,
            dense_rank() OVER (PARTITION BY cdn.chunk_full_name ORDER BY adn.node_name) + cdn.cnt r
        FROM chunk_repl_status cdn
        JOIN (
            SELECT 
                h.hypertable_schema || '.' || h.hypertable_name ht_full_name,
                unnest(h.data_nodes) node_name 
            FROM timescaledb_information.hypertables h
        ) adn 
        ON 
            cdn.ht_full_name = adn.ht_full_name
            AND cdn.node_name <> adn.node_name 
            AND adn.node_name NOT IN (
                SELECT 
                    node_name 
                FROM chunk_repl_status x 
                WHERE x.chunk_full_name = cdn.chunk_full_name
            )
    ) chunk_src_dest
    WHERE
        chunk_src_dest.r <= chunk_src_dest.replication_factor
    ORDER BY chunk_src_dest.chunk_full_name, chunk_src_dest.dst_node_name, random();
END;
$$;

-- Creates 5 metric tables and populates them with 2 hours of data
CREATE OR REPLACE PROCEDURE metric_table_setup()
AS $proc$
DECLARE
    i INTEGER := 0;
BEGIN
    FOR i IN 0..5
    LOOP
        EXECUTE format('CREATE TABLE metric%1s (ts TIMESTAMPTZ NOT NULL, val FLOAT8 NOT NULL, dev_id INT4 NOT NULL)', i);
        PERFORM create_distributed_hypertable(format('metric%1$s', i), 'ts', 'dev_id', chunk_time_interval => INTERVAL '1 hour', replication_factor => 3);

        EXECUTE format('INSERT INTO metric%1$s (ts, val, dev_id) SELECT s.*, 3.14+1, d.* FROM generate_series(''2021-08-17 00:00:00''::timestamp, ''2021-08-17 01:59:59''::timestamp, ''1 s''::interval) s CROSS JOIN generate_series(1, 50) d', i);
    END LOOP;
END
$proc$
LANGUAGE PLPGSQL;

CALL metric_table_setup();