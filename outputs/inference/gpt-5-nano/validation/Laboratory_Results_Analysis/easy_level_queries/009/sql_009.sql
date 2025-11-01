WITH acs_women_hadm AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = di.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  WHERE LOWER(p.gender) = 'female'
    AND REGEXP_CONTAINS(LOWER(dd.long_title),
                        r'(acute myocardial infarction|unstable angina|acute coronary syndrome)')
),

nadir_troponin_per_hadm AS (
  SELECT le.hadm_id,
         MIN(le.valuenum) AS nadir_troponin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dlab
    ON dlab.itemid = le.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON le.hadm_id = a.hadm_id
  WHERE le.hadm_id IN (SELECT hadm_id FROM acs_women_hadm)
    AND LOWER(dlab.label) LIKE '%troponin%'
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN a.admittime AND a.dischtime
  GROUP BY le.hadm_id
),

p25 AS (
  SELECT quantiles[OFFSET(25)] AS p25
  FROM (
    SELECT APPROX_QUANTILES(nadir_troponin, 100) AS quantiles
    FROM nadir_troponin_per_hadm
  )
)

SELECT p25
FROM p25;