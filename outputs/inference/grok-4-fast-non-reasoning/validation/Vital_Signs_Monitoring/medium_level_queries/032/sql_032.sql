WITH vent_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE (LOWER(label) LIKE '%tidal volume%' OR 
         LOWER(label) LIKE '%peep%' OR 
         LOWER(label) LIKE '%resp rate%' OR 
         LOWER(label) LIKE '%ventilator%') 
    AND category = 'Ventilator'
),
stepdown_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (LOWER(t.careunit) LIKE '%stepdown%' OR LOWER(t.careunit) LIKE '%imc%')
),
ventilated_stays AS (
  SELECT DISTINCT i.subject_id, i.hadm_id, i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.subject_id = ce.subject_id 
    AND i.hadm_id = ce.hadm_id 
    AND i.stay_id = ce.stay_id
  INNER JOIN vent_itemids v ON ce.itemid = v.itemid
  WHERE ce.valuenum IS NOT NULL
)
SELECT STDDEV(ce.valuenum) AS nighttime_sbp_stddev_mmHg
FROM ventilated_stays vs
INNER JOIN stepdown_patients sp 
  ON vs.subject_id = sp.subject_id AND vs.hadm_id = sp.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON vs.subject_id = ce.subject_id 
  AND vs.hadm_id = ce.hadm_id 
  AND vs.stay_id = ce.stay_id
WHERE (ce.itemid = 220045 OR ce.itemid = 220179)  -- SBP itemids
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0 AND ce.valuenum < 300  -- Sanity bounds
  AND EXTRACT(HOUR FROM ce.charttime) BETWEEN 0 AND 5;