WITH hf_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    pat.gender,
    pat.anchor_age,
    -- ICU flag
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  -- join ICU to flag
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON adm.hadm_id = icu.hadm_id
  -- only relevant age/gender and HF diagnosis
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 44 AND 54
    AND adm.hadm_id IN (
      SELECT DISTINCT di.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE ( (di.icd_version = 9 AND di.icd_code LIKE '428%')
           OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') )
    )
),
charlson_map AS (
  -- simplified charlson score mapping per hadm_id
  SELECT
    di.hadm_id,
    MAX( CASE WHEN ( (di.icd_version=9 AND di.icd_code LIKE '428%')
                 OR (di.icd_version=10 AND di.icd_code LIKE 'I50%') ) THEN 1 ELSE 0 END ) as chf,
    MAX( CASE WHEN ( (di.icd_version=9 AND di.icd_code BETWEEN '140' AND '239')
                 OR (di.icd_version=10 AND di.icd_code BETWEEN 'C00' AND 'C97') ) THEN 2 ELSE 0 END ) as cancer,
    0 AS dummy -- placeholder
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.hadm_id
),
charlson_score AS (
  SELECT
    hadm_id,
    (chf + cancer) AS score -- simplified, placeholder
  FROM charlson_map
),
me_flags AS (
  SELECT DISTINCT hadm_id, 1 AS mechvent_flag
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE LOWER(ordercategorydescription) LIKE '%vent%'
),
vp_flags AS (
  SELECT DISTINCT hadm_id, 1 AS vaso_flag
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE LOWER(ordercategorydescription) LIKE '%vasopressor%'
),
rrt_flags AS (
  SELECT DISTINCT hadm_id, 1 AS rrt_flag
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE LOWER(ordercategorydescription) LIKE '%dialysis%'
)
SELECT
  CASE WHEN icu_flag=1 THEN 'ICU' ELSE 'No ICU' END AS icu_group,
  CASE WHEN los_days <= 7 THEN 'LOS≤7' ELSE 'LOS>7' END AS los_group,
  CASE WHEN cs.score <= 1 THEN 'Charlson 0–1'
       WHEN cs.score = 2 THEN 'Charlson 2'
       ELSE 'Charlson ≥3' END AS charlson_group,
  COUNT(*) AS n,
  100.0*SUM(hospital_expire_flag)/COUNT(*) AS mortality_pct,
  -- 95% CI in %
  100.0*(SUM(hospital_expire_flag)/COUNT(*) 
         - 1.96*SQRT( (SUM(hospital_expire_flag)/COUNT(*) * (1 - SUM(hospital_expire_flag)/COUNT(*) )) / COUNT(*) )) AS mortality_ci_lower_pct,
  100.0*(SUM(hospital_expire_flag)/COUNT(*) 
         + 1.96*SQRT( (SUM(hospital_expire_flag)/COUNT(*) * (1 - SUM(hospital_expire_flag)/COUNT(*) )) / COUNT(*) )) AS mortality_ci_upper_pct,
  100.0*SUM(IF(mv.mechvent_flag=1,1,0))/COUNT(*) AS mechvent_pct,
  100.0*SUM(IF(vp.vaso_flag=1,1,0))/COUNT(*) AS vasopressor_pct,
  100.0*SUM(IF(rrt.rrt_flag=1,1,0))/COUNT(*) AS rrt_pct
FROM hf_admissions ha
LEFT JOIN charlson_score cs
  ON ha.hadm_id = cs.hadm_id
LEFT JOIN me_flags mv
  ON ha.hadm_id = mv.hadm_id
LEFT JOIN vp_flags vp
  ON ha.hadm_id = vp.hadm_id
LEFT JOIN rrt_flags rrt
  ON ha.hadm_id = rrt.hadm_id
GROUP BY icu_group, los_group, charlson_group
ORDER BY icu_group, los_group, charlson_group;