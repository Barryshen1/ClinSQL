WITH -- Define male ACS admissions
ACS_male_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (
      LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
      OR LOWER(dd.long_title) LIKE '%unstable angina%'
      OR LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
    )
),

-- Compute per-admission peak troponin values during the admission
Troponin_peaks AS (
  SELECT am.hadm_id,
         MAX(le.valuenum) AS peak_troponin
  FROM ACS_male_admissions AS am
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON adm.hadm_id = am.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = am.hadm_id AND le.subject_id = am.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON le.itemid = li.itemid
  WHERE le.charttime >= adm.admittime
    AND le.charttime <= adm.dischtime
    AND le.valuenum IS NOT NULL
    AND LOWER(li.label) LIKE '%troponin%'
    AND LOWER(li.fluid) LIKE '%serum%'
  GROUP BY am.hadm_id
)

-- 75th percentile across all per-admission peak troponin values
SELECT
  quantiles[OFFSET(75)] AS p75_peak_troponin_serum
FROM (
  SELECT APPROX_QUANTILES(peak_troponin, 100) AS quantiles
  FROM Troponin_peaks
) AS q;