WITH filtered_stays AS (
  SELECT 
    ie.stay_id,
    ie.intime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 51 AND 61
),
rr_measurements AS (
  SELECT 
    fs.stay_id,
    ce.charttime,
    ce.valuenum AS rr_value
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id;