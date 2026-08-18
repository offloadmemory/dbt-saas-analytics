import csv
from faker import Faker
from datetime import datetime, timedelta
import random

fake = Faker()


# Function to generate random payment data
def generate_payment():
    return {
        "payment_id": fake.uuid4(),
        "customer_id": fake.uuid4(),
        "amount": round(random.uniform(10.0, 500.0), 2),
        "currency": random.choice(["USD", "EUR"]),
        "created_at": fake.date_time_between(
            start_date="-30d", end_date="now"
        ).strftime("%Y-%m-%d %H:%M:%S"),
    }


# Generate 1000 payment records
payments = [generate_payment() for _ in range(1000)]

# Write data to CSV file
csv_file_path = "stripe_payments_sample.csv"
csv_columns = ["payment_id", "customer_id", "amount", "currency", "created_at"]

with open(csv_file_path, "w", newline="") as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=csv_columns)
    writer.writeheader()
    for payment in payments:
        writer.writerow(payment)

print(f"Sample CSV file with 1000 records generated: {csv_file_path}")
