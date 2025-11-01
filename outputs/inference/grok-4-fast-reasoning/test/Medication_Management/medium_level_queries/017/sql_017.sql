WITH has_dm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250.%')
     OR (icd_version = 10 AND icd_code LIKE 'E1[0-4]%')
),
has_hf AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
hadms_with_dm_hf AS (
  SELECT hd.hadm_id
  FROM has_dm hd
  INNER JOIN has_hf hh ON hd.hadm_id = hh.hadm_id
),
qualifying_stays AS (
  SELECT i.stay_id, i.intime, i.outtime, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  INNER JOIN hadms_with_dm_hf h ON i.hadm_id = h.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age >= 37 AND p.anchor_age <= 47
    AND i.los >= 144
),
relevant_inputs AS (
  SELECT 
    ie.stay_id,
    ie.starttime,
    ie.endtime,
    CASE 
      WHEN LOWER(di.label) LIKE '%insulin%' 
        OR LOWER(di.label) LIKE '%metformin%' 
        OR LOWER(di.label) LIKE '%glipizide%' 
        OR LOWER(di.label) LIKE '%glyburide%' 
        OR LOWER(di.label) LIKE '%sitagliptin%' 
        OR LOWER(di.label) LIKE '%empagliflozin%' 
        OR LOWER(di.label) LIKE '%dulaglutide%' 
        THEN 'Antidiabetics'
      WHEN LOWER(di.label) LIKE '%metoprolol%' 
        OR LOWER(di.label) LIKE '%esmolol%' 
        OR LOWER(di.label) LIKE '%propranolol%' 
        OR LOWER(di.label) LIKE '%atenolol%' 
        OR LOWER(di.label) LIKE '%labetalol%' 
        OR LOWER(di.label) LIKE '%carvedilol%' 
        OR LOWER(di.label) LIKE '%bisoprolol%' 
        OR LOWER(di.label) LIKE '%nadolol%' 
        THEN 'Beta-blockers'
      WHEN LOWER(di.label) LIKE '%lisinopril%' 
        OR LOWER(di.label) LIKE '%enalapril%' 
        OR LOWER(di.label) LIKE '%ramipril%' 
        OR LOWER(di.label) LIKE '%captopril%' 
        OR LOWER(di.label) LIKE '%benazepril%' 
        OR LOWER(di.label) LIKE '%losartan%' 
        OR LOWER(di.label) LIKE '%valsartan%' 
        OR LOWER(di.label) LIKE '%candesartan%' 
        OR LOWER(di.label) LIKE '%irbesartan%' 
        OR LOWER(di.label) LIKE '%telmisartan%' 
        OR LOWER(di.label) LIKE '%olmesartan%' 
        OR LOWER(di.label) LIKE '%entresto%' 
        OR LOWER(di.label) LIKE '%sacubitril%' 
        THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(di.label) LIKE '%furosemide%' 
        OR LOWER(di.label) LIKE '%lasix%' 
        OR LOWER(di.label) LIKE '%bumetanide%' 
        OR LOWER(di.label) LIKE '%torsemide%' 
        OR LOWER(di.label) LIKE '%demadex%' 
        THEN 'Loop Diuretics'
      ELSE NULL
    END AS med_class
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE ie.stay_id IN (SELECT stay_id FROM qualifying_stays)
    AND di.category = 'Medications'
),
filtered_relevant AS (
  SELECT stay_id, med_class, starttime, endtime
  FROM relevant_inputs
  WHERE med_class IS NOT NULL
),
exposures AS (
  SELECT 
    qs.stay_id,
    classes.med_class,
    MAX(IF(fr.starttime IS NOT NULL 
           AND fr.starttime < TIMESTAMP_ADD(qs.intime, INTERVAL 72 HOUR)
           AND COALESCE(fr.endtime, qs.outtime) > qs.intime, 1, 0)) AS exposed_first,
    MAX(IF(fr.starttime IS NOT NULL 
           AND fr.starttime < qs.outtime
           AND COALESCE(fr.endtime, qs.outtime) > TIMESTAMP_SUB(qs.outtime, INTERVAL 72 HOUR), 1, 0)) AS exposed_last
  FROM qualifying_stays qs
  CROSS JOIN (
    SELECT 'Antidiabetics' AS med_class UNION ALL
    SELECT 'Beta-blockers' UNION ALL
    SELECT 'ACEi/ARB/ARNI' UNION ALL
    SELECT 'Loop Diuretics'
  ) classes
  LEFT JOIN filtered_relevant fr 
    ON fr.stay_id = qs.stay_id AND fr.med_class = classes.med_class
  GROUP BY qs.stay_id, classes.med_class
)
SELECT 
  med_class,
  ROUND(AVG(exposed_first) * 100, 2) AS pct_first,
  ROUND(AVG(exposed_last) * 100, 2) AS pct_last,
  COUNTIF(exposed_first = 1 AND exposed_last = 1) AS continued,
  COUNTIF(exposed_first = 0 AND exposed_last = 1) AS initiated,
  COUNTIF(exposed_first = 1 AND exposed_last = 0) AS discontinued,
  COUNT(*) AS total
FROM exposures
GROUP BY med_class
ORDER BY med_class;