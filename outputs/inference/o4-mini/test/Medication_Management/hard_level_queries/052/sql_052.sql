WITH base_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR) AS window_end
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),
hhs_flag AS (
  SELECT
    bc.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        USING (icd_code, icd_version)
      WHERE
        d.hadm_id = bc.hadm_id
        AND LOWER(dd.long_title) LIKE '%hyperosmolar%'
    ) AS has_hhs
  FROM base_cohort bc
),
med_counts AS (
  SELECT
    hf.subject_id,
    hf.hadm_id,
    hf.has_hhs,
    COUNT(DISTINCT pr.drug) AS med_complexity,
    COUNT(DISTINCT IF(
      LOWER(pr.drug) IN (
        'spironolactone','eplerenone',
        'lisinopril','enalapril','ramipril',
        'losartan','valsartan',
        'trimethoprim','pentamidine',
        'potassium chloride','potassium citrate'
      ),
      pr.drug,
      NULL
    )) AS hyperk_count,
    TIMESTAMP_DIFF(hf.dischtime, hf.admittime, HOUR) AS los_hrs,
    hf.hospital_expire_flag
  FROM
    hhs_flag hf
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON pr.hadm_id = hf.hadm_id
      AND pr.starttime < hf.window_end
      AND pr.stoptime > hf.admittime
  GROUP BY
    hf.subject_id,
    hf.hadm_id,
    hf.has_hhs,
    hf.admittime,
    hf.dischtime,
    hf.hospital_expire_flag
),
percentiles AS (
  SELECT
    mc.*,
    PERCENT_RANK() OVER (ORDER BY mc.hyperk_count) AS hyperk_pr
  FROM med_counts mc
),
los_cutoff AS (
  SELECT
    has_hhs,
    APPROX_QUANTILES(los_hrs, 4)[OFFSET(3)] AS los_75th
  FROM percentiles
  GROUP BY has_hhs
)
SELECT
  CASE WHEN mc.has_hhs THEN 'HHS' ELSE 'Non-HHS' END AS cohort,
  -- Medication complexity distribution: 25th, 50th, 75th percentiles
  APPROX_QUANTILES(mc.med_complexity, 4)[OFFSET(0)] AS med_complex_25,
  APPROX_QUANTILES(mc.med_complexity, 4)[OFFSET(1)] AS med_complex_50,
  APPROX_QUANTILES(mc.med_complexity, 4)[OFFSET(2)] AS med_complex_75,
  -- Median percentile rank of hyperkalemia-risk drugs
  APPROX_QUANTILES(mc.hyperk_pr, 2)[OFFSET(1)] AS median_hyperk_pr,
  -- Percent affected by hyperkalemia-risk drugs
  100.0 * SUM(IF(mc.hyperk_count > 0, 1, 0)) / COUNT(*) AS pct_hyperk_affected,
  -- Percent in top-quartile LOS
  100.0 * SUM(IF(mc.los_hrs >= lc.los_75th, 1, 0)) / COUNT(*) AS pct_top_quartile_los,
  -- Mortality among those in top-quartile LOS
  100.0
    * SUM(IF(mc.los_hrs >= lc.los_75th AND mc.hospital_expire_flag = 1, 1, 0))
    / NULLIF(SUM(IF(mc.los_hrs >= lc.los_75th, 1, 0)), 0)
    AS mort_top_quartile_los
FROM percentiles mc
JOIN los_cutoff lc
  ON mc.has_hhs = lc.has_hhs
GROUP BY mc.has_hhs
ORDER BY cohort;