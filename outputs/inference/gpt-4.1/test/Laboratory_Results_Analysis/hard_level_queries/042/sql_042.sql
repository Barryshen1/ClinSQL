WITH ich_codes AS (
  -- ICD-9: 431; ICD-10: I61.x
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code = '431')
     OR (icd_version = 10 AND icd_code LIKE 'I61%')
),
ich_admissions AS (
  -- Male, age 73-83, with ICH diagnosis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN ich_codes icd
    ON dx.icd_code = icd.icd_code AND dx.icd_version = icd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 73 AND 83
),
lab_abnormal AS (
  -- For each admission, get abnormal labs in first 48h
  SELECT
    le.hadm_id,
    dlab.label AS lab_type
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN ich_admissions ia
    ON le.hadm_id = ia.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  WHERE
    DATETIME(le.charttime) >= DATETIME(ia.admittime)
    AND DATETIME(le.charttime) < DATETIME_ADD(DATETIME(ia.admittime), INTERVAL 48 HOUR)
    AND (
      -- Abnormal by flag
      (le.flag IS NOT NULL AND LOWER(le.flag) != 'normal')
      -- Or abnormal by value outside ref range
      OR (
        le.flag IS NULL
        AND le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
    )
),
instability_scores AS (
  -- Count unique abnormal lab types per admission
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.anchor_age,
    ia.gender,
    ia.admittime,
    ia.dischtime,
    ia.hospital_expire_flag,
    COUNT(DISTINCT lab.lab_type) AS instability_score
  FROM ich_admissions ia
  LEFT JOIN lab_abnormal lab
    ON ia.hadm_id = lab.hadm_id
  GROUP BY
    ia.subject_id, ia.hadm_id, ia.anchor_age, ia.gender,
    ia.admittime, ia.dischtime, ia.hospital_expire_flag
),
quartiles AS (
  -- Assign quartiles based on instability score
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS instability_quartile,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM instability_scores
),
quartile_stats AS (
  -- Aggregate stats per quartile
  SELECT
    instability_quartile,
    COUNT(*) AS admission_count,
    ROUND(AVG(los_days),2) AS mean_los_days,
    ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)),3) AS mortality_rate
  FROM quartiles
  GROUP BY instability_quartile
  ORDER BY instability_quartile
),

-- For comparison: all inpatients
all_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
),
all_lab_abnormal AS (
  SELECT
    le.hadm_id,
    dlab.label AS lab_type
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN all_admissions aa
    ON le.hadm_id = aa.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  WHERE
    DATETIME(le.charttime) >= DATETIME(aa.admittime)
    AND DATETIME(le.charttime) < DATETIME_ADD(DATETIME(aa.admittime), INTERVAL 48 HOUR)
    AND (
      (le.flag IS NOT NULL AND LOWER(le.flag) != 'normal')
      OR (
        le.flag IS NULL
        AND le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
    )
),
all_instability_scores AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    aa.anchor_age,
    aa.gender,
    aa.admittime,
    aa.dischtime,
    aa.hospital_expire_flag,
    COUNT(DISTINCT lab.lab_type) AS instability_score
  FROM all_admissions aa
  LEFT JOIN all_lab_abnormal lab
    ON aa.hadm_id = lab.hadm_id
  GROUP BY
    aa.subject_id, aa.hadm_id, aa.anchor_age, aa.gender,
    aa.admittime, aa.dischtime, aa.hospital_expire_flag
),
all_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS instability_quartile,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM all_instability_scores
),
all_quartile_stats AS (
  SELECT
    instability_quartile,
    COUNT(*) AS admission_count,
    ROUND(AVG(los_days),2) AS mean_los_days,
    ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)),3) AS mortality_rate
  FROM all_quartiles
  GROUP BY instability_quartile
  ORDER BY instability_quartile
)

-- Final output: ICH cohort quartiles and all inpatient quartiles
SELECT
  'ICH cohort' AS cohort,
  instability_quartile,
  admission_count,
  mean_los_days,
  mortality_rate
FROM quartile_stats

UNION ALL

SELECT
  'All inpatients' AS cohort,
  instability_quartile,
  admission_count,
  mean_los_days,
  mortality_rate
FROM all_quartile_stats
ORDER BY cohort, instability_quartile;