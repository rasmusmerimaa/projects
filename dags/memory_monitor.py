from airflow import DAG
from airflow.operators.python import BranchPythonOperator
from airflow.operators.dummy import DummyOperator
from airflow.operators.email import EmailOperator
from datetime import datetime, timedelta
import psutil

def branch_memory_check(**kwargs):
    ti = kwargs['ti']
    mem = psutil.virtual_memory()
    used_mb = mem.used / (1024 * 1024)
    ti.xcom_push(key="memory_used_mb", value=used_mb)

    threshold_mb = 100
    if used_mb > threshold_mb:
        return "send_email"
    else:
        return "do_nothing"

default_args = {
    "owner": "airflow",
    "start_date": datetime(2025, 2, 3),
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
        dag_id="memory_monitor_dag",
        default_args=default_args,
        schedule_interval="* * * * *",
        catchup=False,
) as dag:

    branching = BranchPythonOperator(
        task_id="branch_memory_check",
        python_callable=branch_memory_check,
        provide_context=True,
    )

    send_email = EmailOperator(
        task_id="send_email",
        to="your_email@example.com",
        subject="Airflow Memory Alert",
        html_content=(
            "<h3>Memory Usage Alert</h3>"
            "<p>The memory usage exceeded the threshold. Check the logs for details.</p>"
        ),
    )

    do_nothing = DummyOperator(task_id="do_nothing")

    branching >> [send_email, do_nothing]
