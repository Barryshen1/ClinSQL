WITH patient_cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),

prescriptions_in_first_24h AS (
  SELECT
    p.hadm_id,
    p.drug,
    p.starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    patient_cohort pc
  ON
    p.hadm_id = pc.hadm_id
  WHERE
    p.starttime >= pc.admittime
    AND p.starttime <= pc.admittime + INTERVAL '24' HOUR
),

medication_complexity AS (
  SELECT
    pc.hadm_id,
    COUNT(DISTINCT p.drug) AS medication_count
  FROM
    patient_cohort pc
  LEFT JOIN
    prescriptions_in_first_24h p
  ON
    pc.hadm_id = p.hadm_id
  GROUP BY
    pc.hadm_id
),

percentile_calc AS (
  SELECT
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY medication_count) AS top_quartile
  FROM
    medication_complexity
),

top_quartile_patients AS (
  SELECT
    mc.hadm_id,
    pc.admittime,
    pc.dischtime,
    pc.hospital_expire_flag
  FROM
    medication_complexity mc
  JOIN
    patient_cohort pc
  ON
    mc.hadm_id = pc.hadm_id
  CROSS JOIN
    percentile_calc pc2
  WHERE
    mc.medication_count >= pc2.top_quartile
)

SELECT
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  top_quartile_patients;