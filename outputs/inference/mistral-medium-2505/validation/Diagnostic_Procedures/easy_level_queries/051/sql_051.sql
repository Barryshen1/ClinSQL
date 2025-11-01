WITH male_patients_41_51 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 41 AND 51
),

ecg_telemetry_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
  ON
    p.itemid = d.itemid
  WHERE
    (LOWER(d.label) LIKE '%ecg%'
     OR LOWER(d.label) LIKE '%telemetry%')
    AND p.subject_id IN (SELECT subject_id FROM male_patients_41_51)
),

procedures_per_patient AS (
  SELECT
    subject_id,
    COUNT(DISTINCT itemid) AS distinct_ecg_telemetry_count
  FROM
    ecg_telemetry_procedures
  GROUP BY
    subject_id
)

SELECT
  PERCENTILE_CONT(distinct_ecg_telemetry_count, 0.75) OVER() AS percentile_75
FROM
  procedures_per_patient
LIMIT 1;