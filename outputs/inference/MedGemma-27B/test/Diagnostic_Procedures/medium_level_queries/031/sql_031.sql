CASE
      WHEN f.deathtime IS NOT NULL THEN TIMESTAMP_DIFF(f.deathtime, f.admittime, DAY)
      ELSE TIMESTAMP_DIFF(f.dischtime, f.admittime, DAY)
    END AS admission_length_days;