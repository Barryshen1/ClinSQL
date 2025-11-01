WITH first_spo2 AS (
  SELECT
    ce.hadm_id,
    ce.valuenum AS spo2,
    ROW_NUMBER() OVER (PARTITION BY ce.hadm_id ORDER BY ce.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    di.label = 'SpO2'
    AND di.category = 'Vital Signs'
    AND ce.valuenum IS NOT NULL
),
first_spo2_per_admission AS (
  SELECT
    hadm_id,
    spo2
  FROM
    first_spo2
  WHERE
    rn = 1
)
SELECT
  STDDEV_POP(spo2) AS spo2_stddev
FROM
  first_spo2_per_admission
WHERE
  hadm_id IN (
    SELECT
      a.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 77 AND 87
  );