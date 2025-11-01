WITH lab_items AS (
  SELECT
    itemid,
    CASE
      WHEN LOWER(label) LIKE '%creatinine%' THEN 'Creatinine'
      WHEN LOWER(label) LIKE '%potassium%' AND LOWER(fluid) NOT LIKE '%whole blood%' THEN 'Potassium'
      WHEN LOWER(label) LIKE '%platelet%' THEN 'Platelets'
      WHEN LOWER(label) LIKE '%hemoglobin%' THEN 'Hemoglobin'
      WHEN LOWER(label) LIKE '%potassium%' AND LOWER(fluid) LIKE '%whole blood%' THEN 'WholeBlood_K'
      WHEN LOWER(label) LIKE '%wbc%' OR LOWER(label) LIKE '%leukocyte%' THEN 'WBC'
      ELSE NULL
    END AS lab_name
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE
    LOWER(label) LIKE '%creatinine%'
    OR LOWER(label) LIKE '%potassium%'
    OR LOWER(label) LIKE '%platelet%'
    OR LOWER(label) LIKE '%hemoglobin%'
    OR LOWER(label) LIKE '%wbc%'
    OR LOWER(label) LIKE '%leukocyte%'
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
lab_instability AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNTIF(
      (
        le.flag = 'abnormal'
        OR (le.valuenum IS NOT NULL AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        ))
      )
    ) AS instability_score,
    -- For each lab, did patient have at least one critical value?
    MAX(IF(li.lab_name = 'Creatinine' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_Cr,
    MAX(IF(li.lab_name = 'Potassium' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_K,
    MAX(IF(li.lab_name = 'Platelets' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_Platelets,
    MAX(IF(li.lab_name = 'Hemoglobin' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_Hgb,
    MAX(IF(li.lab_name = 'WholeBlood_K' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_WholeBlood_K,
    MAX(IF(li.lab_name = 'WBC' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_WBC
  FROM cohort c
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  LEFT JOIN lab_items li
    ON le.itemid = li.itemid
  WHERE li.lab_name IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
),
percentile_90 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM lab_instability
),
top_tier AS (
  SELECT
    li.subject_id,
    li.hadm_id,
    li.instability_score,
    li.crit_Cr,
    li.crit_K,
    li.crit_Platelets,
    li.crit_Hgb,
    li.crit_WholeBlood_K,
    li.crit_WBC,
    c.hospital_expire_flag,
    c.admittime,
    c.dischtime
  FROM lab_instability li
  JOIN cohort c
    ON li.subject_id = c.subject_id AND li.hadm_id = c.hadm_id
  JOIN percentile_90 p
    ON li.instability_score >= p.p90_score
),
top_tier_stats AS (
  SELECT
    COUNT(*) AS n_top_tier,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS avg_LOS_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(CAST(crit_Cr AS FLOAT64)) AS rate_Cr,
    AVG(CAST(crit_K AS FLOAT64)) AS rate_K,
    AVG(CAST(crit_Platelets AS FLOAT64)) AS rate_Platelets,
    AVG(CAST(crit_Hgb AS FLOAT64)) AS rate_Hgb,
    AVG(CAST(crit_WholeBlood_K AS FLOAT64)) AS rate_WholeBlood_K,
    AVG(CAST(crit_WBC AS FLOAT64)) AS rate_WBC
  FROM top_tier
),
all_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    MAX(IF(li.lab_name = 'Creatinine' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_Cr,
    MAX(IF(li.lab_name = 'Potassium' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_K,
    MAX(IF(li.lab_name = 'Platelets' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_Platelets,
    MAX(IF(li.lab_name = 'Hemoglobin' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_Hgb,
    MAX(IF(li.lab_name = 'WholeBlood_K' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_WholeBlood_K,
    MAX(IF(li.lab_name = 'WBC' AND (
      le.flag = 'abnormal'
      OR (le.valuenum IS NOT NULL AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
        OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
      ))
    ), 1, 0)) AS crit_WBC
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  LEFT JOIN lab_items li
    ON le.itemid = li.itemid
  WHERE li.lab_name IS NOT NULL
  GROUP BY a.subject_id, a.hadm_id
),
all_inpatients_stats AS (
  SELECT
    COUNT(*) AS n_all_inpatients,
    AVG(CAST(crit_Cr AS FLOAT64)) AS rate_Cr,
    AVG(CAST(crit_K AS FLOAT64)) AS rate_K,
    AVG(CAST(crit_Platelets AS FLOAT64)) AS rate_Platelets,
    AVG(CAST(crit_Hgb AS FLOAT64)) AS rate_Hgb,
    AVG(CAST(crit_WholeBlood_K AS FLOAT64)) AS rate_WholeBlood_K,
    AVG(CAST(crit_WBC AS FLOAT64)) AS rate_WBC
  FROM all_inpatients
)
SELECT
  p.p90_score AS lab_instability_score_90th_percentile,
  tts.n_top_tier AS n_top_tier_patients,
  tts.mortality_rate AS top_tier_mortality_rate,
  tts.avg_LOS_days AS top_tier_avg_LOS_days,
  tts.rate_Cr AS top_tier_critical_rate_Cr,
  tts.rate_K AS top_tier_critical_rate_K,
  tts.rate_Platelets AS top_tier_critical_rate_Platelets,
  tts.rate_Hgb AS top_tier_critical_rate_Hgb,
  tts.rate_WholeBlood_K AS top_tier_critical_rate_WholeBlood_K,
  tts.rate_WBC AS top_tier_critical_rate_WBC,
  ais.n_all_inpatients AS n_all_inpatients,
  ais.rate_Cr AS all_inpatients_critical_rate_Cr,
  ais.rate_K AS all_inpatients_critical_rate_K,
  ais.rate_Platelets AS all_inpatients_critical_rate_Platelets,
  ais.rate_Hgb AS all_inpatients_critical_rate_Hgb,
  ais.rate_WholeBlood_K AS all_inpatients_critical_rate_WholeBlood_K,
  ais.rate_WBC AS all_inpatients_critical_rate_WBC
FROM percentile_90 p
CROSS JOIN top_tier_stats tts
CROSS JOIN all_inpatients_stats ais;