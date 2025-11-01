WITH hemorrhagic_stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.anchor_age = 87
    AND p.gender = 'F'
    AND (
      -- ICD-10 hemorrhagic stroke
      (d.icd_version = 10 AND (
        LEFT(d.icd_code, 3) IN ('I60', 'I61', 'I62')
      ))
      -- ICD-9 hemorrhagic stroke
      OR (d.icd_version = 9 AND (
        d.icd_code IN ('430', '431', '432')
      ))
    )
),
platelet_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%platelet%'
),
discharge_day_platelets AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    l.valuenum
  FROM
    hemorrhagic_stroke_admissions h
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON h.subject_id = l.subject_id
      AND h.hadm_id = l.hadm_id
    INNER JOIN platelet_itemids pi
      ON l.itemid = pi.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND DATE(l.charttime) = DATE(h.dischtime)
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS platelet_75th_percentile
FROM
  discharge_day_platelets
;