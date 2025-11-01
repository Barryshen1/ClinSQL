WITH hemorrhagic_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
    ON dic.icd_code = di.icd_code AND dic.icd_version = di.icd_version
  WHERE
    (dic.long_title LIKE '%hemorrhagic%'
     OR dic.long_title LIKE '%intracerebral hemorrhage%'
     OR dic.long_title LIKE '%subarachnoid hemorrhage%')
),
female_87ish AS (
  SELECT h.subject_id, h.hadm_id, h.dischtime
  FROM hemorrhagic_admissions h
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = h.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 95
),
discharge_platelets AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    l.charttime,
    l.valuenum
  FROM female_87ish AS f
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.hadm_id = f.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS lab
    ON lab.itemid = l.itemid
  WHERE LOWER(lab.label) LIKE '%platelet%'
    AND DATE(l.charttime) = DATE(f.dischtime)
),
ranked AS (
  SELECT
    subject_id,
    valuenum AS platelet_value,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY valuenum) AS rn,
    COUNT(*) OVER (PARTITION BY subject_id) AS cnt
  FROM discharge_platelets
),
per_subject_p75 AS (
  SELECT
    subject_id,
    MAX(CASE WHEN rn = CEILING(0.75 * cnt) THEN platelet_value END) AS p75_platelet_on_discharge
  FROM ranked
  GROUP BY subject_id
)
SELECT
  subject_id,
  p75_platelet_on_discharge
FROM per_subject_p75
ORDER BY subject_id;