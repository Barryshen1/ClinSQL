WITH pneumonia_admissions AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%pneumonia%'
    AND di.icd_version = 10
),
male_pneumonia_creatinine AS (
  SELECT le.hadm_id, MAX(le.valuenum) AS peak_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  JOIN pneumonia_admissions pa
    ON le.hadm_id = pa.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON le.subject_id = p.subject_id
  WHERE dlab.label = 'Creatinine'
    AND LOWER(dlab.fluid) = 'blood'
    AND p.gender = 'M'
    AND le.valuenum IS NOT NULL
  GROUP BY le.hadm_id
)
SELECT STDDEV(peak_creatinine) AS std_dev_peak_creatinine
FROM male_pneumonia_creatinine;