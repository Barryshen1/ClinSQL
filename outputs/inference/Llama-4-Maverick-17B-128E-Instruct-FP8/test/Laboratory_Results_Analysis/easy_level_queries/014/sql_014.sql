WITH gi_bleeding_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Gastrointestinal hemorrhage%' OR d_icd.long_title LIKE '%GI bleed%'
),
relevant_patients AS (
  SELECT pat.subject_id, adm.hadm_id, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  WHERE pat.gender = 'F' AND pat.anchor_age BETWEEN 44 AND 46  
    AND adm.hadm_id IN (SELECT hadm_id FROM gi_bleeding_admissions)
),
discharge_day_hemoglobin AS (
  SELECT rp.hadm_id, lab.valuenum AS hemoglobin
  FROM relevant_patients rp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON rp.hadm_id = lab.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab
    ON lab.itemid = d_lab.itemid
  WHERE d_lab.label LIKE '%Hemoglobin%' AND DATE(lab.charttime) = DATE(rp.dischtime)
)
SELECT APPROX_QUANTILES(hemoglobin, 100)[OFFSET(75)] AS percentile_75th
FROM discharge_day_hemoglobin;