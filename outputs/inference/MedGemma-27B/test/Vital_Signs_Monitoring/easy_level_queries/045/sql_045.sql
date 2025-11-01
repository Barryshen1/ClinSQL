WITH PatientAge AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 51 AND 61
),
FirstRR AS (
  SELECT
    ce.subject_id,
    ce.valuenum AS respiratory_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ce.subject_id = p.subject_id
  WHERE
    ce.itemid = 220187 -- Respiratory Rate itemid
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom = 'times/min'
    AND ce.charttime = (
      SELECT
        MIN(charttime)
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_min
      WHERE
        ce_min.subject_id = ce.subject_id
        AND ce_min.stay_id = ce.stay_id
        AND ce_min.itemid = 220187
    )
)
SELECT
  STDDEV(respiratory_rate)
FROM FirstRR
WHERE
  subject_id IN (
    SELECT
      subject_id
    FROM PatientAge
  );