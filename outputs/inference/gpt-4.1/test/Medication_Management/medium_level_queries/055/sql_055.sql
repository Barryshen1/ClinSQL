WITH
-- 1. Identify T2DM and HF ICD codes
t2dm_icds AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250[.]([0-9]*[02])$')) -- 250.x0, 250.x2
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E11'))
),
hf_icds AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428'))
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
),

-- 2. Admissions with both T2DM and HF
admissions_with_t2dm_hf AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN (
    SELECT d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN t2dm_icds t ON d.icd_code = t.icd_code AND d.icd_version = t.icd_version
    GROUP BY d.hadm_id
  ) t2dm ON a.hadm_id = t2dm.hadm_id
  JOIN (
    SELECT d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN hf_icds h ON d.icd_code = h.icd_code AND d.icd_version = h.icd_version
    GROUP BY d.hadm_id
  ) hf ON a.hadm_id = hf.hadm_id
),

-- 3. Female patients age 39-49
female_39_49 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 39 AND 49
),

-- 4. ICU stays for cohort, LOS >= 72h
cohort_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN admissions_with_t2dm_hf adm ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
  JOIN female_39_49 f ON icu.subject_id = f.subject_id
  WHERE icu.los >= 3 -- LOS in days
),

-- 5. Insulin itemids from d_items
insulin_items AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%insulin%'
),

-- 6. Classify insulin types (basal, bolus) by label
insulin_types AS (
  SELECT
    itemid,
    CASE
      WHEN REGEXP_CONTAINS(label, r'glargine|detemir|degludec|basal') THEN 'basal'
      WHEN REGEXP_CONTAINS(label, r'regular|lispro|aspart|glulisine|bolus|short|rapid') THEN 'bolus'
      ELSE 'other'
    END AS insulin_type
  FROM insulin_items
),

-- 7. All insulin administrations in ICU stays
insulin_admins AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.starttime,
    it.insulin_type,
    LOWER(ie.ordercategorydescription) AS ordercategorydescription
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN insulin_types it ON ie.itemid = it.itemid
  WHERE it.insulin_type IN ('basal', 'bolus')
),

-- 8. Sliding-scale detection (by ordercategorydescription or label)
sliding_scale_admins AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.starttime
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN insulin_items it ON ie.itemid = it.itemid
  WHERE LOWER(ie.ordercategorydescription) LIKE '%sliding%'
    OR LOWER(it.label) LIKE '%sliding%'
),

-- 9. For each stay, determine regimen in first 72h and final 48h
regimen_by_stay AS (
  SELECT
    cs.stay_id,
    cs.subject_id,
    cs.hadm_id,
    -- First 72h window
    MAX(CASE WHEN ia.starttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 72 HOUR) AND ia.insulin_type = 'basal' THEN 1 ELSE 0 END) AS basal_72h,
    MAX(CASE WHEN ia.starttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 72 HOUR) AND ia.insulin_type = 'bolus' THEN 1 ELSE 0 END) AS bolus_72h,
    MAX(CASE WHEN ss.starttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS sliding_72h,
    -- Final 48h window
    MAX(CASE WHEN ia.starttime BETWEEN DATETIME_SUB(cs.outtime, INTERVAL 48 HOUR) AND cs.outtime AND ia.insulin_type = 'basal' THEN 1 ELSE 0 END) AS basal_48h,
    MAX(CASE WHEN ia.starttime BETWEEN DATETIME_SUB(cs.outtime, INTERVAL 48 HOUR) AND cs.outtime AND ia.insulin_type = 'bolus' THEN 1 ELSE 0 END) AS bolus_48h,
    MAX(CASE WHEN ss.starttime BETWEEN DATETIME_SUB(cs.outtime, INTERVAL 48 HOUR) AND cs.outtime THEN 1 ELSE 0 END) AS sliding_48h
  FROM cohort_stays cs
  LEFT JOIN insulin_admins ia ON cs.stay_id = ia.stay_id
  LEFT JOIN sliding_scale_admins ss ON cs.stay_id = ss.stay_id
  GROUP BY cs.stay_id, cs.subject_id, cs.hadm_id, cs.intime, cs.outtime
),

-- 10. Assign regimen per window
regimen_flags AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    -- First 72h
    CASE
      WHEN basal_72h = 1 AND bolus_72h = 1 THEN 'basal-bolus'
      WHEN basal_72h = 1 THEN 'basal'
      WHEN bolus_72h = 1 THEN 'bolus'
      ELSE NULL
    END AS regimen_72h,
    sliding_72h,
    -- Final 48h
    CASE
      WHEN basal_48h = 1 AND bolus_48h = 1 THEN 'basal-bolus'
      WHEN basal_48h = 1 THEN 'basal'
      WHEN bolus_48h = 1 THEN 'bolus'
      ELSE NULL
    END AS regimen_48h,
    sliding_48h
  FROM regimen_by_stay
),

-- 11. Aggregate percentages
counts AS (
  SELECT
    COUNT(*) AS n_stays,
    COUNTIF(regimen_72h = 'basal') AS n_basal_72h,
    COUNTIF(regimen_72h = 'bolus') AS n_bolus_72h,
    COUNTIF(regimen_72h = 'basal-bolus') AS n_basalbolus_72h,
    COUNTIF(sliding_72h = 1) AS n_sliding_72h,
    COUNTIF(regimen_48h = 'basal') AS n_basal_48h,
    COUNTIF(regimen_48h = 'bolus') AS n_bolus_48h,
    COUNTIF(regimen_48h = 'basal-bolus') AS n_basalbolus_48h,
    COUNTIF(sliding_48h = 1) AS n_sliding_48h
  FROM regimen_flags
)

SELECT
  'basal' AS regimen,
  ROUND(100.0 * n_basal_72h / n_stays, 1) AS pct_72h,
  ROUND(100.0 * n_basal_48h / n_stays, 1) AS pct_48h,
  ROUND(ABS(100.0 * n_basal_48h / n_stays - 100.0 * n_basal_72h / n_stays), 1) AS abs_pct_point_diff
FROM counts
UNION ALL
SELECT
  'bolus',
  ROUND(100.0 * n_bolus_72h / n_stays, 1),
  ROUND(100.0 * n_bolus_48h / n_stays, 1),
  ROUND(ABS(100.0 * n_bolus_48h / n_stays - 100.0 * n_bolus_72h / n_stays), 1)
FROM counts
UNION ALL
SELECT
  'basal-bolus',
  ROUND(100.0 * n_basalbolus_72h / n_stays, 1),
  ROUND(100.0 * n_basalbolus_48h / n_stays, 1),
  ROUND(ABS(100.0 * n_basalbolus_48h / n_stays - 100.0 * n_basalbolus_72h / n_stays), 1)
FROM counts
UNION ALL
SELECT
  'sliding-scale',
  ROUND(100.0 * n_sliding_72h / n_stays, 1),
  ROUND(100.0 * n_sliding_48h / n_stays, 1),
  ROUND(ABS(100.0 * n_sliding_48h / n_stays - 100.0 * n_sliding_72h / n_stays), 1)
FROM counts
ORDER BY regimen;