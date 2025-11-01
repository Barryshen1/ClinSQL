WITH spo2_first AS (
  SELECT
    p.subject_id,
    adm.hadm_id,
    ce.charttime,
    ce.valuenum AS spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON ce.subject_id = adm.subject_id
    AND ce.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ce.subject_id = p.subject_id
  WHERE LOWER(di.label) = 'spo2'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= adm.admittime
  QUALIFY ROW_NUMBER() OVER (
      PARTITION BY ce.subject_id, ce.hadm_id
      ORDER BY ce.charttime ASC
  ) = 1
)
SELECT
  STDDEV_SAMP(spo2) AS spo2_stddev
FROM spo2_first;