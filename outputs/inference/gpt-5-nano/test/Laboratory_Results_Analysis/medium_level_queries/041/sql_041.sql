WITH ACS_admissions AS (
  SELECT DISTINCT a.hadm_id,
                  a.subject_id AS patient_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
      LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
      OR LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
      OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
      OR LOWER(dd.long_title) LIKE '%unstable angina%'
    )
),

TroponinEvents AS (
  SELECT
    acs.hadm_id,
    acs.patient_id,
    le.charttime,
    le.valuenum,
    LOWER(le.valueuom) AS unit
  FROM ACS_admissions AS acs
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = acs.patient_id AND le.hadm_id = acs.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE (
        LOWER(dli.label) LIKE '%troponin%' 
        AND (
          LOWER(dli.label) LIKE '%troponin t%'
          OR LOWER(dli.label) LIKE '%troponin t high sensitivity%'
          OR LOWER(dli.label) LIKE '%troponin t hs%'
        )
      )
    AND LOWER(le.valueuom) LIKE '%ng/ml%'
),

FirstTroponin AS (
  SELECT hadm_id,
         patient_id,
         charttime,
         valuenum
  FROM (
    SELECT t.*,
           ROW_NUMBER() OVER (PARTITION BY t.hadm_id ORDER BY t.charttime ASC) AS rn
    FROM TroponinEvents AS t
  )
  WHERE rn = 1
    AND valuenum > 0.014  -- above ULN for hs-TnT in ng/mL
),

Quantiles AS (
  SELECT APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM FirstTroponin
)

SELECT
  Q.quantiles[OFFSET(2)] AS median_initial_hsTnT_ng_per_ml,
  (Q.quantiles[OFFSET(3)] - Q.quantiles[OFFSET(1)]) AS iqr_ng_per_ml
FROM Quantiles AS Q;