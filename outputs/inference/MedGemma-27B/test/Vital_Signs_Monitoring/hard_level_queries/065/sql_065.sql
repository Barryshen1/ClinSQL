WITH PatientAge AS (
  SELECT
    subject_id,
    CASE
      WHEN anchor_age >= 70 AND anchor_age < 80 THEN '70-80'
      ELSE NULL
    END AS age_group
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
), ICUStaysWithAge AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    p.age_group
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  LEFT JOIN PatientAge AS p
    ON s.subject_id = p.subject_id
  WHERE
    p.age_group = '70-80'
), VitalSigns AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.charttime,
    s.valuenum AS map_value,
    s.valueuom AS map_uom
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS s
  WHERE
    s.itemid = 455 -- MAP
), RRT AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.transfers`
  WHERE
    careunit = 'RRT'
), VitalInstability AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    -- Calculate hypotension episodes (MAP < 65)
    SUM(CASE WHEN vs.map_value < 65 THEN 1 ELSE 0 END) AS hypotension_episodes,
    -- Calculate tachycardia episodes (HR > 100)
    SUM(CASE WHEN vs.hr_value > 100 THEN 1 ELSE 0 END) AS tachycardia_episodes,
    -- Calculate bradycardia episodes (HR < 50)
    SUM(CASE WHEN vs.hr_value < 50 THEN 1 ELSE 0 END) AS bradycardia_episodes,
    -- Calculate tachypnea episodes (RR > 25)
    SUM(CASE WHEN vs.rr_value > 25 THEN 1 ELSE 0 END) AS tachypnea_episodes,
    -- Calculate bradypnea episodes (RR < 10)
    SUM(CASE WHEN vs.rr_value < 10 THEN 1 ELSE 0 END) AS bradypnea_episodes,
    -- Calculate SpO2 < 90 episodes
    SUM(CASE WHEN vs.spo2_value < 90 THEN 1 ELSE 0 END) AS spo2_low_episodes
  FROM ICUStaysWithAge AS icu
  LEFT JOIN VitalSigns AS vs
    ON icu.subject_id = vs.subject_id AND icu.hadm_id = vs.hadm_id AND icu.stay_id = vs.stay_id
  WHERE
    icu.subject_id IN (SELECT subject_id FROM RRT)
  GROUP BY
    icu.subject_id,;