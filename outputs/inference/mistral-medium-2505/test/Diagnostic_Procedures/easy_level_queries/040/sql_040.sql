WITH male_patients_51_61 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),

ecg_telemetry_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    pe.itemid
  FROM
    male_patients_51_61 p
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON p.subject_id = pe.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE
    (LOWER(di.label) LIKE '%ecg%'
     OR LOWER(di.label) LIKE '%telemetry%'
     OR LOWER(di.category) LIKE '%ecg%'
     OR LOWER(di.category) LIKE '%telemetry%')
),

procedure_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT itemid) AS distinct_ecg_telemetry_count
  FROM
    ecg_telemetry_procedures
  GROUP BY
    subject_id
)

SELECT
  PERCENTILE_CONT(distinct_ecg_telemetry_count, 0.25) OVER() AS percentile_25
FROM
  procedure_counts
LIMIT 1;