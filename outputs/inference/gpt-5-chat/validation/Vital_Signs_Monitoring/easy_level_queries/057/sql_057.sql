WITH rr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
    AND LOWER(unitname) LIKE '%breath%'
),
rr_per_stay AS (
  SELECT
    ie.stay_id,
    MAX(ce.valuenum) AS max_rr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND ce.itemid IN (SELECT itemid FROM rr_items)
    AND ce.valuenum IS NOT NULL
  GROUP BY ie.stay_id
)
SELECT MIN(max_rr) AS min_of_max_rr
FROM rr_per_stay;