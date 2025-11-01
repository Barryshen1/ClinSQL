WITH pneumonia_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
),
male_pneumonia AS (
  SELECT pa.subject_id, pa.hadm_id
  FROM pneumonia_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON pa.subject_id = pt.subject_id
  WHERE pt.gender = 'M'
),
creatinine_labitems AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) = 'serum'
),
peak_creatinine_per_adm AS (
  SELECT mp.hadm_id,
         MAX(le.valuenum) AS peak_creatinine
  FROM male_pneumonia mp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON mp.hadm_id = le.hadm_id
  WHERE le.itemid IN (SELECT itemid FROM creatinine_labitems)
    AND le.valuenum IS NOT NULL
  GROUP BY mp.hadm_id
)
SELECT STDDEV(peak_creatinine) AS stddev_peak_creatinine
FROM peak_creatinine_per_adm;