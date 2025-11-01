WITH cohort AS (
  -- female inpatients age 71-81 with an acute pancreatitis diagnosis on the admission
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diags
    ON a.subject_id = diags.subject_id AND a.hadm_id = diags.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dcode
    ON diags.icd_code = dcode.icd_code AND diags.icd_version = dcode.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND LOWER(dcode.long_title) LIKE '%acute pancreat%'
),

presc_within_72h AS (
  -- for each admission in cohort, aggregate prescriptions that overlap first 72 hours
  SELECT
    c.hadm_id,
    COUNT(DISTINCT LOWER(TRIM(pr.drug))) AS n_unique_drugs,
    SUM(
      CASE
        WHEN pr.doses_per_24_hrs IS NULL OR pr.doses_per_24_hrs = 0 THEN 1
        ELSE pr.doses_per_24_hrs
      END
    ) AS sum_freq,
    COUNT(pr.hadm_id) AS n_prescriptions
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
    -- require that the prescription has at least some identifying information
    AND (pr.drug IS NOT NULL OR pr.doses_per_24_hrs IS NOT NULL OR pr.pharmacy_id IS NOT NULL)
    -- overlap condition: prescription interval intersects [admittime, admittime + 72h]
    -- cast prescription datetimes to TIMESTAMP so types match admissions' TIMESTAMPs
    AND COALESCE(TIMESTAMP(pr.stoptime), TIMESTAMP('9999-12-31 00:00:00')) >= c.admittime
    AND TIMESTAMP(pr.starttime) <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),

med_scores AS (
  -- combine cohort + prescription aggregates, compute med_score and outcomes
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COALESCE(pw.n_unique_drugs, 0) AS n_unique_drugs,
    COALESCE(pw.sum_freq, 0) AS sum_freq,
    COALESCE(pw.n_prescriptions, 0) AS n_prescriptions,
    -- medication complexity score: distinct drugs + sum of dosing frequencies (missing freq -> 1)
    (COALESCE(pw.n_unique_drugs, 0) + COALESCE(pw.sum_freq, 0)) AS med_score,
    -- LOS in days (as float)
    SAFE_DIVIDE(TIMESTAMP_DIFF(c.dischtime, c.admittime, MINUTE), 1440.0) AS los_days,
    -- compute 30-day readmission indicator (1 if any subsequent admission within 30 days)
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmit30
  FROM cohort c
  LEFT JOIN presc_within_72h pw
    ON c.hadm_id = pw.hadm_id
),

with_tertile AS (
  -- assign tertiles by med_score (approximately equal-sized groups)
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_score) AS tertile
  FROM med_scores
)

-- final aggregation per tertile
SELECT
  tertile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(med_score), 2) AS avg_med_score,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS in_hospital_mortality_pct,
  ROUND(100.0 * SUM(readmit30) / COUNT(*), 2) AS readmit_30d_pct
FROM with_tertile
GROUP BY tertile
ORDER BY tertile;