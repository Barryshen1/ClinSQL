WITH qualifying_stays AS (
  SELECT 
    i.stay_id, 
    i.subject_id, 
    i.intime, 
    i.outtime,
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 81 AND 91
),
hfnc_stays AS (
  SELECT DISTINCT qs.stay_id
  FROM qualifying_stays qs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON c.subject_id = qs.subject_id 
    AND c.stay_id = qs.stay_id
  WHERE c.itemid = 225477
    AND (LOWER(c.value) LIKE '%high flow%' OR LOWER(c.value) LIKE '%hfnc%')
    AND c.charttime >= qs.intime
    AND c.charttime <= qs.outtime
),
sbp_per_stay AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.stay_id IN (SELECT stay_id FROM hfnc_stays)
    AND ce.itemid IN (220045, 220179)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= (
      SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` ic 
      WHERE ic.stay_id = ce.stay_id
    )
    AND ce.charttime <= (
      SELECT outtime FROM `physionet-data.mimiciv_3_1_icu.icustays` ic 
      WHERE ic.stay_id = ce.stay_id
    )
  GROUP BY ce.stay_id
)
SELECT MIN(mean_sbp) AS min_per_stay_mean_sbp
FROM sbp_per_stay
WHERE mean_sbp IS NOT NULL;