WITH diabetes_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  WHERE LOWER(dd.long_title) LIKE '%diabetes%'
),
heartfailure_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),
eligible_stays AS (
  SELECT ic.stay_id, ic.hadm_id, ic.subject_id, ic.intime, ic.outtime, ic.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = ic.subject_id
  JOIN diabetes_hadm d ON d.hadm_id = ic.hadm_id
  JOIN heartfailure_hadm h ON h.hadm_id = ic.hadm_id
  WHERE ic.los >= 96
    AND (LOWER(p.gender) = 'f' OR LOWER(p.gender) = 'female')
    AND p.anchor_age BETWEEN 65 AND 75
),
regimen_by_window AS (
  SELECT es.stay_id,
         es.intime,
         es.outtime,
         -- First 48h regimen
         CASE
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
             JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ie.itemid
             WHERE ie.stay_id = es.stay_id
               AND LOWER(di.label) LIKE '%insulin%'
               AND ie.charttime >= es.intime
               AND ie.charttime < es.intime + INTERVAL 48 HOUR
               AND LOWER(ie.ordercategorydescription) LIKE '%bolus%'
           )
           AND EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
             JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ie.itemid
             WHERE ie.stay_id = es.stay_id
               AND LOWER(di.label) LIKE '%insulin%'
               AND ie.charttime >= es.intime
               AND ie.charttime < es.intime + INTERVAL 48 HOUR
               AND LOWER(ie.ordercategorydescription) LIKE '%basal%'
           )
           THEN 'basal_bolus'
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
             JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ie.itemid
             WHERE ie.stay_id = es.stay_id
               AND LOWER(di.label) LIKE '%insulin%'
               AND ie.charttime >= es.intime
               AND ie.charttime < es.intime + INTERVAL 48 HOUR
               AND LOWER(ie.ordercategorydescription) LIKE '%sliding scale%'
           )
           THEN 'sliding_scale'
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
             JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ie.itemid
             WHERE ie.stay_id = es.stay_id
               AND LOWER(di.label) LIKE '%insulin%'
               AND ie.charttime >= es.intime
               AND ie.charttime < es.intime + INTERVAL 48 HOUR
               AND LOWER(ie.ordercategorydescription) LIKE '%basal%'
           )
           THEN 'basal'
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
             JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ie.itemid
             WHERE ie.stay_id = es.stay_id
               AND LOWER(di.label) LIKE '%insulin%'
               AND ie.charttime >= es.intime
               AND ie.charttime < es.intime + INTERVAL 48 HOUR
               AND LOWER(ie.ordercategorydescription) LIKE '%bolus%'
           )
           THEN 'bolus'
           ELSE 'none'
           END AS first_regimen,
         -- Last 48h regimen
         CASE
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
             JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ie.itemid
             WHERE ie.stay_id = es.stay_id
               AND LOWER(di.label) LIKE '%insulin%'
               AND ie.charttime >= es.outtime - INTERVAL 48 HOUR
               AND ie.charttime <= es.outtime
               AND LOWER(ie.ordercategorydescription) LIKE '%basal%'
           )
           AND EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
             JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ie.itemid
             WHERE ie.stay_id = es.stay_id
               AND LOWER(di.label) LIKE '%insulin%'
               AND ie.charttime >= es.outtime - INTERVAL 48 HOUR
               AND ie.charttime <= es.outtime
               AND LOWER(ie.ordercategorydescription) LIKE '%bolus%'
           )
           THEN 'basal_bolus'
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
             JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ie.itemid
             WHERE ie.stay_id = es.stay_id
               AND LOWER(di.label) LIKE '%insulin%'
               AND ie.charttime >= es.outtime - INTERVAL 48 HOUR
               AND ie.charttime <= es.outtime
               AND LOWER(ie.ordercategorydescription) LIKE '%sliding scale%'
           )
           THEN 'sliding_scale'
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
             JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ie.itemid
             WHERE ie.stay_id = es.stay_id
               AND LOWER(di.label) LIKE '%insulin%'
               AND ie.charttime >= es.outtime - INTERVAL 48 HOUR
               AND ie.charttime <= es.outtime
               AND LOWER(ie.ordercategorydescription) LIKE '%basal%'
           )
           THEN 'basal'
           WHEN EXISTS (
             SELECT 1
             FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
             JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ie.itemid
             WHERE ie.stay_id = es.stay_id
               AND LOWER(di.label) LIKE '%insulin%'
               AND ie.charttime >= es.outtime - INTERVAL 48 HOUR
               AND ie.charttime <= es.outtime
               AND LOWER(ie.ordercategorydescription) LIKE '%bolus%'
           )
           THEN 'bolus'
           ELSE 'none'
           END AS last_regimen
  FROM eligible_stays es
),
first_tot AS (
  SELECT COUNT(*) AS total
  FROM regimen_by_window
  WHERE first_regimen IN ('basal','bolus','basal_bolus','sliding_scale')
),
first_dist AS (
  SELECT first_regimen AS regimen, COUNT(*) AS n
  FROM regimen_by_window
  WHERE first_regimen IN ('basal','bolus','basal_bolus','sliding_scale')
  GROUP BY first_regimen
),
final_tot AS (
  SELECT COUNT(*) AS total
  FROM regimen_by_window
  WHERE last_regimen IN ('basal','bolus','basal_bolus','sliding_scale')
),
final_dist AS (
  SELECT last_regimen AS regimen, COUNT(*) AS n
  FROM regimen_by_window
  WHERE last_regimen IN ('basal','bolus','basal_bolus','sliding_scale')
  GROUP BY last_regimen
),
trans_tot AS (
  SELECT COUNT(*) AS total FROM regimen_by_window
),
trans_dist AS (
  SELECT CONCAT(first_regimen, ' → ', last_regimen) AS transition, COUNT(*) AS n
  FROM regimen_by_window
  GROUP BY transition
)

SELECT
  'First 48h' AS window_label,
  regimen,
  n,
  100.0 * n / (SELECT total FROM first_tot) AS pct
FROM first_dist
UNION ALL
SELECT
  'Final 48h' AS window_label,
  regimen,
  n,
  100.0 * n / (SELECT total FROM final_tot) AS pct
FROM final_dist
UNION ALL
SELECT
  transition AS window_label,
  NULL AS regimen,
  n,
  100.0 * n / (SELECT total FROM trans_tot) AS pct
FROM trans_dist
ORDER BY window_label, (regimen IS NULL) DESC, pct DESC;