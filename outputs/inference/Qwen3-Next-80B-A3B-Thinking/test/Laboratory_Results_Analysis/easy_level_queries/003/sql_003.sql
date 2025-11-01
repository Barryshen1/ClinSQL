WITH male_acs AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND (LOWER(d.long_title) LIKE '%acute coronary syndrome%'
         OR LOWER(d.long_title) LIKE '%myocardial infarction%'
         OR LOWER(d.long_title) LIKE '%unstable angina%')
),
troponin_events AS (
  SELECT le.hadm_id, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
  WHERE LOWER(dl.label) LIKE '%troponin%'
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN a.admittime AND a.dischtime
),
peak_troponin AS (
  SELECT t.hadm_id, MAX(t.valuenum) AS peak_troponin
  FROM troponin_events t
  WHERE t.hadm_id IN (SELECT hadm_id FROM male_acs)
  GROUP BY t.hadm_id
)
SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY peak_troponin) AS percentile_75
FROM peak_troponin;