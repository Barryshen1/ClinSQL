WITH ap_diagnoses AS (
  -- Identify admissions with acute pancreatitis, mark primary vs secondary
  SELECT
    di.subject_id,
    di.hadm_id,
    CASE
      WHEN di.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diag_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute pancreatitis%'
),
cohort AS (
  -- Restrict to male patients age 51-61 with AP admissions
  SELECT
    a.subject_id,
    a.hadm_id,
    pd.diag_type,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN ap_diagnoses pd
      ON a.hadm_id = pd.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
los_binned AS (
  -- Compute LOS and bucket into 1-3 vs 4-7 days
  SELECT
    c.*,
    DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1 AS los_days,
    CASE
      WHEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1 BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1 BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group
  FROM
    cohort c
),
rad_counts AS (
  -- Count radiography/CT events per admission
  SELECT
    lb.hadm_id,
    lb.diag_type,
    lb.los_group,
    COUNT(he.hcpcs_cd) AS radiology_count
  FROM
    los_binned lb
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
      ON lb.hadm_id = he.hadm_id
     AND DATE(he.chartdate) BETWEEN DATE(lb.admittime) AND DATE(lb.dischtime)
     AND (
       LOWER(he.short_description) LIKE '%xray%'
       OR LOWER(he.short_description) LIKE '%ct%'
     )
  WHERE
    lb.los_group IS NOT NULL
  GROUP BY
    lb.hadm_id,
    lb.diag_type,
    lb.los_group
)
SELECT
  rc.diag_type,
  rc.los_group,
  COUNT(DISTINCT rc.hadm_id) AS num_admissions,
  ROUND(AVG(rc.radiology_count), 2) AS mean_radiology_per_admission
FROM
  rad_counts rc
GROUP BY
  rc.diag_type,
  rc.los_group
ORDER BY
  rc.diag_type,
  rc.los_group;