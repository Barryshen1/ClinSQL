WITH 
hs_tnt_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%hs-TnT%' OR label LIKE '%High Sensitivity Troponin T%'
),
first_hs_tnt AS (
  SELECT le.hadm_id, le.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN hs_tnt_itemid ON le.itemid = hs_tnt_itemid.itemid
),
relevant_admissions AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime,
         EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age as age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND a.admittime IS NOT NULL AND a.dischtime IS NOT NULL
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 81 AND 91
),
chest_pain_ami_admissions AS (
  SELECT ra.hadm_id
  FROM relevant_admissions ra
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ra.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Myocardial Infarction%' OR dicd.long_title LIKE '%Chest Pain%'
),
hs_tnt_category AS (
  SELECT fht.hadm_id, fht.valuenum,
         CASE 
           WHEN fht.valuenum < 14 THEN 'Normal'
           WHEN fht.valuenum BETWEEN 14 AND 52 THEN 'Borderline'
           ELSE 'Myocardial Injury'
         END as category,
         DATETIME_DIFF(ra.dischtime, ra.admittime, HOUR) / 24.0 as los
  FROM first_hs_tnt fht
  JOIN chest_pain_ami_admissions cpa ON fht.hadm_id = cpa.hadm_id
  JOIN relevant_admissions ra ON fht.hadm_id = ra.hadm_id
  WHERE fht.rn = 1
)
SELECT category, COUNT(*) as count, 
       COUNT(*) * 100.0 / (SELECT COUNT(*) FROM hs_tnt_category) as percentage,
       AVG(los) as mean_los
FROM hs_tnt_category
GROUP BY category
ORDER BY category;