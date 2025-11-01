WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 37 AND 47
),
FirstSpO2 AS (
  SELECT
    ic.subject_id,
    ce.charttime AS first_spo2_charttime,
    ce.valuenum AS first_spo2_value
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ic.subject_id = ce.subject_id AND ic.hadm_id = ce.hadm_id AND ic.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220180 -- SpO2 itemid
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ic.subject_id,
    ce.charttime,
    ce.valuenum
)
SELECT
  PERCENTILE_CONT(0.25, first_spo2_value) AS IQR_25,
  PERCENTILE_CONT(0.75, first_spo2_value) AS IQR_75
FROM
  FirstSpO2
WHERE
  first_spo2_charttime = (
    SELECT
      MIN(first_spo2_charttime)
    FROM
      FirstSpO2
    WHERE
      first_spo2_charttime = first_spo2_charttime
  );