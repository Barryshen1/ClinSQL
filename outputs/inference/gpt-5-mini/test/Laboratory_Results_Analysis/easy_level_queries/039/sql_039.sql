WITH pneumonia_adms AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%pneumonia%'
),
male_95_adms AS (
  SELECT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age = 95
),
target_admissions AS (
  -- admissions that are pneumonia AND male 95
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_95_adms m USING(hadm_id)
  JOIN pneumonia_adms pn USING(hadm_id)
),
creatinine_items AS (
  -- choose lab itemids likely representing serum/blood/plasma creatinine
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND (
      LOWER(fluid) IN ('blood','serum','plasma')
      OR LOWER(label) LIKE '%serum%'
    )
),
peak_creatinine_by_adm AS (
  SELECT t.hadm_id,
         MAX(l.valuenum) AS peak_creatinine
  FROM target_admissions t
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.hadm_id = t.hadm_id
   AND l.subject_id = t.subject_id
  JOIN creatinine_items ci
    ON l.itemid = ci.itemid
  WHERE l.valuenum IS NOT NULL
    AND l.charttime BETWEEN t.admittime AND t.dischtime
  GROUP BY t.hadm_id
)
SELECT
  STDDEV_SAMP(peak_creatinine) AS sd_peak_creatinine,
  COUNT(*) AS n_admissions_with_creatinine
FROM peak_creatinine_by_adm
WHERE peak_creatinine > 0;