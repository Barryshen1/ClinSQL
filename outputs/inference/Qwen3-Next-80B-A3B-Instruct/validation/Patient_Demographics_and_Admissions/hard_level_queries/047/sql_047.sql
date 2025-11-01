WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    p.anchor_age,
    p.gender,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND d.seq_num = 1  -- principal diagnosis
    AND (
      LOWER(dicd.long_title) LIKE '%hemorrhagic stroke%'
      OR LOWER(dicd.long_title) LIKE '%intracerebral hemorrhage%'
      OR LOWER(dicd.long_title) LIKE '%subarachnoid hemorrhage%'
      OR LOWER(dicd.long_title) LIKE '%intracranial hemorrhage%'
    )
),
readmission_flag AS (
  SELECT
    c.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_hosp.admissions a2
        WHERE a2.subject_id = c.subject_id
          AND a2.hadm_id != c.hadm_id
          AND a2.admittime >= c.dischtime
          AND a2.admittime <= DATE_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted
  FROM
    cohort c
)
SELECT
  SUM(readmitted) * 1.0 / COUNT(*) AS readmission_rate,
  (SELECT PERCENTILE_CONT(los, 0.5) FROM readmission_flag WHERE readmitted = 1) AS median_los_readmitted,
  (SELECT PERCENTILE_CONT(los, 0.5) FROM readmission_flag WHERE readmitted = 0) AS median_los_non_readmitted,
  SUM(CASE WHEN los > 4 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS pct_los_gt_4_days
FROM
  readmission_flag;