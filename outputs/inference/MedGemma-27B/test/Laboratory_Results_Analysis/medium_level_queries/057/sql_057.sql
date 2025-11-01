WITH FirstTroponin AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid = 50178 -- Troponin T
    AND valuenum IS NOT NULL
    AND valueuom = 'ng/mL'
  GROUP BY
    subject_id,
    hadm_id
),
AdmissionDiagnosis AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_version = 9 -- Use ICD-9 for ACS codes
    AND d.icd_code IN ('410', '411', '414') -- ACS codes in ICD-9
)
SELECT
  CASE
    WHEN ft.valuenum <= 0.04 THEN 'Normal (≤0.04)'
    WHEN ft.valuenum > 0.04 AND ft.valuenum <= 0.1 THEN 'Borderline (>0.04–0.1)'
    WHEN ft.valuenum > 0.1 THEN 'Elevated (>0.1)'
    ELSE 'Other'
  END AS troponin_category,
  COUNT(DISTINCT ft.subject_id) AS admission_count
FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ft
INNER JOIN FirstTroponin AS first_t
  ON ft.subject_id = first_t.subject_id AND ft.hadm_id = first_t.hadm_id AND ft.charttime = first_t.first_charttime
INNER JOIN AdmissionDiagnosis AS ad
  ON ft.subject_id = ad.subject_id AND ft.hadm_id = ad.hadm_id
WHERE
  ft.itemid = 50178 -- Troponin T
  AND ft.valuenum IS NOT NULL
  AND ft.valueuom = 'ng/mL'
GROUP BY
  troponin_category
ORDER BY
  CASE
    WHEN troponin_category = 'Normal (≤0.04)' THEN 1
    WHEN troponin_category = 'Borderline (>0.04–0.1)' THEN 2
    WHEN troponin_category = 'Elevated (>0.1)' THEN 3
    ELSE 4
  END;