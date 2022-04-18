from subprocess import Popen, PIPE
from concurrent import futures

def exec_cmd(cmd):
    """Execute the given command returning stdout, stderr, and the return code"""

    proc = Popen(cmd, stdout=PIPE, stdin=PIPE, stderr=PIPE, universal_newlines=True)
    out, err = proc.communicate()

    return { "stdout": out, "stderr": err, "returncode": proc.returncode }


def exec_copy(copy_params):
    """Issues a copy command to copy a chunk from one data node to another"""

    if len(copy_params) < 3:
        return
        
    chunk_name = copy_params[0].strip()
    src_dn = copy_params[1].strip()
    dst_dn = copy_params[2].strip()

    print("Copying chunk %s from %s to %s" % (chunk_name, src_dn, dst_dn))

    # full chunk name, src node name, dest node name
    copy_stmt = """CALL timescaledb_experimental.copy_chunk('%s'::regclass, '%s'::name, '%s'::name);""" % (chunk_name, src_dn, dst_dn)
    copy_cmd = ['psql', "-h", "localhost", "-p", "5433", "-U", "postgres", "-d", "testdb", "-c", copy_stmt]
    res = exec_cmd(copy_cmd)

    if res["returncode"]:
        print("Copy for chunk: %s from: %s to: %s failed" % (chunk_name, src_dn, dst_dn))
        print("stdout: " + res["stdout"])
        print("stderr: " + res["stderr"])
    else:
        print("Copy for chunk: %s from: %s to: %s succeeded" % (chunk_name, src_dn, dst_dn))


def ensure_chunks_fully_replicated():
    """Finds under replicated chunks and replicates them to other nodes to ensure that all chunks are at the desired replication factor"""

    replication_plan = ["psql", "-t", "-h", "localhost", "-p", "5433", "-U", "postgres", "-d", "testdb", "-c", """SELECT * FROM get_chunk_repl_restore_plan();"""]
    res = exec_cmd(replication_plan)

    if res["returncode"]:
        print("Failed to get re-replication plan")
        print("stdout:\n" + res["stdout"])
        print("stderr:\n" + res["stderr"])
        exit(1)

    copy_params = map(lambda x: x.split("|"), res["stdout"].splitlines()[:-1])

    # A single work will complete successfully 
    # The more workers the more likely there are to be errors
    with futures.ThreadPoolExecutor(max_workers=8) as executor:
        tasks = executor.map(exec_copy, copy_params)
        list(tasks)

if __name__ == '__main__':
    ensure_chunks_fully_replicated()