WITH female_elderly AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),
hfnc_stays AS (
  SELECT DISTINCT ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN female_elderly fe
    ON ie.subject_id = fe.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ie.stay_id = pe.stay_id
  WHERE LOWER(pe.ordercategoryname) LIKE '%high flow%'
     OR LOWER(pe.ordercategorydescription) LIKE '%high flow%'
     OR LOWER(pe.ordercategoryname) LIKE '%nasal cannula%'
     OR LOWER(pe.ordercategorydescription) LIKE '%nasal cannula%'
),
sbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%' 
    AND LOWER(label) LIKE '%blood%' 
    AND LOWER(label) LIKE '%pressure%'
),
sbp_per_stay AS (
  SELECT ce.stay_id,
         AVG(ce.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN sbp_itemids di
    ON ce.itemid = di.itemid
  JOIN hfnc_stays hs
    ON ce.stay_id = hs.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300
  GROUP BY ce.stay_id
)
SELECT MIN(mean_sbp) AS min_per_stay_mean_sbp
FROM sbp_per_stay;