WITH stroke_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id,  -- Fixed erroneous leading dot
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,  -- Fixed timestamp handling
    CASE 
      WHEN diag.icd_version = 9 AND diag.icd_code LIKE '433%' THEN 'ischemic'
      WHEN diag.icd_version = 9 AND diag.icd_code LIKE '434%' THEN 'ischemic'
      WHEN diag.icd_version = 9 AND diag.icd_code = '436' THEN 'ischemic'
      WHEN diag.icd_version = 10 AND diag.icd_code LIKE 'I63%' THEN 'ischemic'
      WHEN diag.icd_version = 10 AND diag.icd_code = 'I67.89' THEN 'ischemic'
      WHEN diag.icd_version = 9 AND diag.icd_code = '430' THEN 'hemorrhagic'
      WHEN diag.icd_version = 9 AND diag.icd_code = '431' THEN 'hemorrhagic'
      WHEN diag.icd_version = 9 AND diag.icd_code LIKE '432%' THEN 'hemorrhagic'
      WHEN diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^I6[0-2]') THEN 'hemorrhagic'  -- Simplified regex
    END AS stroke_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 44 AND 54
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('433%','434%','436','430','431','432%')) 
      OR
      (diag.icd_version = 10 AND (
        diag.icd_code LIKE 'I63%' OR 
        diag.icd_code = 'I67.89' OR 
        REGEXP_CONTAINS(diag.icd_code, r'^I6[0-2]')
      ))
    )
),

charlson AS (
  SELECT 
    hadm_id,
    SUM(weight) AS charlson_score
  FROM (
    SELECT DISTINCT  -- Avoid duplicate diagnoses
      diag.hadm_id,
      CASE 
        WHEN diag.icd_code LIKE '410%' OR diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' THEN 1
        WHEN diag.icd_code LIKE '428%' OR diag.icd_code LIKE 'I50%' THEN 1
        WHEN diag.icd_code LIKE '443%' OR diag.icd_code = '441.2' OR diag.icd_code LIKE 'I70%' OR diag.icd_code LIKE 'I71%' THEN 1
        WHEN diag.icd_code LIKE '290%' OR diag.icd_code LIKE 'F0%' THEN 1
        WHEN diag.icd_code LIKE '49%' OR diag.icd_code LIKE 'J4%' OR diag.icd_code LIKE 'J6%' THEN 1
        WHEN diag.icd_code LIKE '725%' OR diag.icd_code LIKE 'M05%' OR diag.icd_code LIKE 'M06%' OR diag.icd_code LIKE 'M32%' THEN 1
        WHEN diag.icd_code LIKE '53[1-4]%' OR diag.icd_code LIKE 'K2[5-8]%' THEN 1
        WHEN diag.icd_code IN ('571.2','571.5','571.6') OR diag.icd_code LIKE 'K70%' OR diag.icd_code LIKE 'K73%' OR diag.icd_code LIKE 'K74%' THEN 1
        WHEN (diag.icd_version = 9 AND diag.icd_code LIKE '250.%' AND diag.icd_code NOT LIKE '250.[4-7]%') 
             OR (diag.icd_version = 10 AND diag.icd_code LIKE 'E1[0-4]%' AND diag.icd_code NOT LIKE '%2%' AND diag.icd_code NOT LIKE '%3%') THEN 1
        WHEN (diag.icd_version = 9 AND diag.icd_code LIKE '250.[4-7]%') 
             OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'E1[0-4].2%' OR diag.icd_code LIKE 'E1[0-4].3%')) THEN 2
        WHEN diag.icd_code LIKE '344%' OR diag.icd_code LIKE 'G8[1-2]%' THEN 2
        WHEN diag.icd_code LIKE '58%' OR diag.icd_code LIKE 'N18%' OR diag.icd_code LIKE 'N19%' THEN 2
        WHEN diag.icd_code BETWEEN '140' AND '199' OR diag.icd_code LIKE 'C%' THEN 2
        WHEN diag.icd_code LIKE '456%' OR diag.icd_code LIKE '572%' OR diag.icd_code LIKE 'I85%' OR diag.icd_code LIKE 'K7[0-2]%' OR diag.icd_code LIKE 'K76.[5-7]' THEN 3
        WHEN diag.icd_code BETWEEN '196' AND '199' OR diag.icd_code LIKE 'C7[7-9]%' OR diag.icd_code LIKE 'C80%' THEN 6
        WHEN diag.icd_code LIKE '04[2-4]%' OR diag.icd_code LIKE 'B2[0-4]%' THEN 6
        ELSE 0
      END AS weight
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE hadm_id IN (SELECT hadm_id FROM stroke_admissions)
      -- Correctly exclude ONLY stroke codes (not all cerebrovascular diseases)
      AND NOT (
        (icd_version = 9 AND icd_code IN ('433%','434%','436','430','431','432%')) OR
        (icd_version = 10 AND (icd_code LIKE 'I63%' OR icd_code = 'I67.89' OR REGEXP_CONTAINS(icd_code, r'^I6[0-2]')))
      )
  )
  GROUP BY hadm_id
),

interventions AS (
  SELECT 
    sa.hadm_id,
    MAX(CASE WHEN pe.itemid IN (225468, 225477, 227194) THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN ie.itemid IN (221906, 222168, 221289, 221750, 221662, 222315, 221749) THEN 1 ELSE 0 END) AS vasopressors,  -- Removed dobutamine
    MAX(CASE WHEN pe.itemid IN (225802, 225803, 225805, 225809) THEN 1 ELSE 0 END) AS rrt
  FROM stroke_admissions sa
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON sa.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON icu.stay_id = pe.stay_id
    AND pe.starttime BETWEEN sa.admittime AND sa.dischtime
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON icu.stay_id = ie.stay_id
    AND ie.starttime BETWEEN sa.admittime AND sa.dischtime
  GROUP BY sa.hadm_id
),

cohort AS (
  SELECT 
    sa.*,
    COALESCE(c.charlson_score, 0) AS charlson_score,
    i.mech_vent,
    i.vasopressors,
    i.rrt,
    CASE 
      WHEN sa.los_days <= 5 THEN '<=5' 
      ELSE '>5' 
    END AS los_group,
    CASE 
      WHEN COALESCE(c.charlson_score, 0) = 0 THEN 'low'
      WHEN COALESCE(c.charlson_score, 0) BETWEEN 1 AND 2 THEN 'med'
      ELSE 'high'
    END AS comorbidity_group
  FROM stroke_admissions sa
  LEFT JOIN charlson c
    ON sa.hadm_id = c.hadm_id
  LEFT JOIN interventions i
    ON sa.hadm_id = i.hadm_id
)

SELECT 
  stroke_type,
  los_group,
  comorbidity_group,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
  ROUND(100.0 * SUM(mech_vent) / COUNT(*), 2) AS percent_mech_vent,
  ROUND(100.0 * SUM(vasopressors) / COUNT(*), 2) AS percent_vasopressors,
  ROUND(100.0 * SUM(rrt) / COUNT(*), 2) AS percent_rrt
FROM cohort
GROUP BY stroke_type, los_group, comorbidity_group
ORDER BY stroke_type, los_group, comorbidity_group;