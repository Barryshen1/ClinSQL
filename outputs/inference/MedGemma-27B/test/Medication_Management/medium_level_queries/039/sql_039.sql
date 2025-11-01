WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
  -- Add conditions for T2DM and heart failure here
),
MedicationOrders AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.charttime,
    m.medication,
    m.route
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` AS m
    ON h.emar_id = m.emar_id
  WHERE
    h.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
    AND m.medication LIKE '%GLP-1%'
    AND m.route = 'SubQ'
),
TimeBuckets AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    CASE
      WHEN charttime BETWEEN (
        SELECT
          MIN(admittime)
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        WHERE
          a.subject_id = MedicationOrders.subject_id
          AND a.hadm_id = MedicationOrders.hadm_id
      ) AND (
        SELECT
          MIN(admittime)
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        WHERE
          a.subject_id = MedicationOrders.subject_id
          AND a.hadm_id = MedicationOrders.hadm_id
      ) + INTERVAL 24 HOUR
      THEN 'First 24h'
      WHEN charttime BETWEEN (
        SELECT
          MIN(admittime)
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        WHERE
          a.subject_id = MedicationOrders.subject_id
          AND a.hadm_id = MedicationOrders.hadm_id
      ) + INTERVAL 24 HOUR AND (
        SELECT
          MIN(admittime)
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        WHERE
          a.subject_id = MedicationOrders.subject_id
          AND a.hadm_id = MedicationOrders.hadm_id
      ) + INTERVAL 48 HOUR
      THEN 'Final 48h'
      ELSE 'Other'
    END AS time_bucket
  FROM MedicationOrders
)
SELECT
  time_bucket,
  COUNT(DISTINCT subject_id) AS num_patients,
  COUNT(DISTINCT subject_id) * 100.0 / (
    SELECT
      COUNT(DISTINCT subject_id)
    FROM PatientCohort
  ) AS prevalence_percent
FROM TimeBuckets
WHERE
  time_bucket IN ('First 24h', 'Final 48h')
GROUP BY
  time_bucket
ORDER BY
  time_bucket;