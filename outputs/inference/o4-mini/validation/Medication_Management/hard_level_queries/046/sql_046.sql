WITH trauma_codes AS (
  -- Identify ICD codes whose description mentions "trauma"
  SELECT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    LOWER(long_title) LIKE '%trauma%'
),
multi_trauma_admissions AS (
  -- Find admissions with at least two trauma diagnoses
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN trauma_codes t
      ON d.icd_code = t.icd_code
      AND d.icd_version = t.icd_version
  GROUP BY
    d.subject_id,
    d.hadm_id
  HAVING
    COUNT(*) >= 2
),
base_cohort AS (
  -- Female inpatients aged 45-55 with multi-trauma
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN multi_trauma_admissions m
      ON a.subject_id = m.subject_id
      AND a.hadm_id = m.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
),
med_complexity AS (
  -- Compute medication complexity: distinct drugs in first 7 days
  SELECT
    b.subject_id,
    b.hadm_id,
    COUNT(DISTINCT pres.drug) AS med_count
  FROM
    base_cohort b
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
      ON b.subject_id = pres.subject_id
      AND b.hadm_id = pres.hadm_id
      AND pres.starttime BETWEEN b.admittime
        AND DATETIME_ADD(b.admittime, INTERVAL 7 DAY)
  GROUP BY
    b.subject_id,
    b.hadm_id
),
readmissions AS (
  -- Flag 30-day readmission
  SELECT
    b.subject_id,
    b.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = b.subject_id
          AND a2.admittime > b.dischtime
          AND a2.admittime <= DATETIME_ADD(b.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit30
  FROM
    base_cohort b
),
indexed AS (
  -- Combine all metrics and compute LOS
  SELECT
    b.subject_id,
    b.hadm_id,
    mc.med_count,
    DATETIME_DIFF(b.dischtime, b.admittime, DAY) AS los,
    b.hospital_expire_flag AS died,
    COALESCE(r.readmit30, 0) AS readmit30
  FROM
    base_cohort b
    LEFT JOIN med_complexity mc
      ON b.subject_id = mc.subject_id
      AND b.hadm_id = mc.hadm_id
    LEFT JOIN readmissions r
      ON b.subject_id = r.subject_id
      AND b.hadm_id = r.hadm_id
),
tertiles AS (
  -- Assign tertiles based on medication complexity
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM
    indexed
)
-- Final aggregation per tertile
SELECT
  tertile,
  COUNT(*) AS admissions,
  ROUND(AVG(med_count), 2) AS avg_med_count,
  MIN(med_count) AS min_med_count,
  MAX(med_count) AS max_med_count,
  ROUND(AVG(los), 2) AS avg_los,
  ROUND(100.0 * SUM(died) / COUNT(*), 1) AS mortality_percent,
  ROUND(100.0 * SUM(readmit30) / COUNT(*), 1) AS readmit30_percent
FROM
  tertiles
GROUP BY
  tertile
ORDER BY
  tertile;