WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE
    gender = 'M' AND anchor_age = 57
),
AgeGroup AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE
    gender = 'M' AND anchor_age BETWEEN 52 AND 62
),
ICUStayInfo AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime,
    chartevents.charttime,
    chartevents.value AS respiratory_rate
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents
    ON icustays.stay_id = chartevents.stay_id
  WHERE
    chartevents.itemid = 220187 -- Respiratory Rate itemid
),
ICUStayDay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    charttime,
    respiratory_rate,
    DATE_DIFF(charttime, intime, DAY) AS icu_day
  FROM ICUStayDay
),
FilteredICUStayDay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    charttime,
    respiratory_rate,
    icu_day
  FROM ICUStayDay
  WHERE
    icu_day >= 2
),
PatientAgeGroup AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE
    gender = 'M' AND anchor_age BETWEEN 52 AND 62
)
SELECT
  MAX(respiratory_rate) AS max_respiratory_rate
FROM FilteredICUStayDay
WHERE
  subject_id IN (
    SELECT
      subject_id
    FROM PatientAgeGroup
  );