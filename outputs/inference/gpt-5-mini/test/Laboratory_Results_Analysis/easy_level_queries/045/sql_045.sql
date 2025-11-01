WITH male_sepsis_adms AS (
  -- male hospital admissions with a diagnosis whose long_title mentions "sepsis"
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    USING (subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code
   AND di.icd_version = dic.icd_version
  WHERE p.gender = 'M'
    AND LOWER(COALESCE(dic.long_title, '')) LIKE '%sepsis%'
),

admission_creat_events AS (
  -- creatinine lab events for those admissions within 24 hours of admittime
  SELECT
    m.subject_id,
    m.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom
  FROM male_sepsis_adms m
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = m.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE LOWER(COALESCE(li.label, '')) LIKE '%creatinine%'
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN m.admittime AND TIMESTAMP_ADD(m.admittime, INTERVAL 1 DAY)
),

admission_creat_first AS (
  -- first creatinine per admission (index creatinine)
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    valueuom,
    charttime,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
  FROM admission_creat_events
)

-- Among male sepsis admissions, return the admission-index creatinine and pick the maximum
SELECT
  hadm_id,
  subject_id,
  valuenum AS admission_index_creatinine,
  valueuom
FROM admission_creat_first
WHERE rn = 1
ORDER BY admission_index_creatinine DESC
LIMIT 1;