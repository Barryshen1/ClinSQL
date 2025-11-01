WITH cohort AS (
  -- 1. Identify male patients age 58-68 with COPD exacerbation admission
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
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND LOWER(dd.long_title) LIKE '%copd exacerbation%'
),
med_complexity AS (
  -- 2. Compute medication complexity score in first 72 hours
  SELECT
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON c.hadm_id = pr.hadm_id
      AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY
    c.hadm_id
),
readmit_flags AS (
  -- 3. Flag 30-day readmissions
  SELECT
    c.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit_30d_flag
  FROM
    cohort c
),
cohort_metrics AS (
  -- 4. Assemble all metrics per admission
  SELECT
    c.hadm_id,
    mc.complexity_score,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los,
    c.hospital_expire_flag AS mortality_flag,
    rf.readmit_30d_flag
  FROM
    cohort c
    LEFT JOIN med_complexity mc USING (hadm_id)
    LEFT JOIN readmit_flags rf USING (hadm_id)
),
tertiles AS (
  -- 5. Assign complexity tertiles
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM
    cohort_metrics
)
-- 6. Aggregate by tertile
SELECT
  tertile,
  COUNT(*) AS n_patients,
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity,
  ROUND(AVG(complexity_score), 2) AS mean_complexity,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(100.0 * SUM(mortality_flag) / COUNT(*), 2) AS mortality_pct,
  ROUND(100.0 * SUM(readmit_30d_flag) / COUNT(*), 2) AS readmit_30d_pct
FROM
  tertiles
GROUP BY
  tertile
ORDER BY
  tertile;