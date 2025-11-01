WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 73 AND 83
),
FirstRR AS (
  SELECT
    p.subject_id,
    ce.charttime AS first_rr_charttime,
    ce.valuenum AS respiratory_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON ce.hadm_id = a.hadm_id
  JOIN PatientInfo AS p
    ON ce.subject_id = p.subject_id
  WHERE
    ce.itemid = 220187 -- Respiratory Rate
    AND ce.valuenum IS NOT NULL
    AND ce.charttime = (
      SELECT
        MIN(charttime)
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_inner
      WHERE
        ce_inner.subject_id = ce.subject_id
        AND ce_inner.hadm_id = ce.hadm_id
        AND ce_inner.itemid = 220187
        AND ce_inner.valuenum IS NOT NULL
    )
)
SELECT
  STDDEV(respiratory_rate) AS sd_respiratory_rate
FROM FirstRR;