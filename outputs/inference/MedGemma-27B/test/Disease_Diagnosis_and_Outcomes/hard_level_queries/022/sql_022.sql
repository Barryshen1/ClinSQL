WITH AKI_Patients AS (
  -- Identify patients with AKI based on ICD-9 codes
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('585', '586', '587', '588', '589', '590', '591', '593', '594', '598', '599', 'N17.9') -- AKI ICD-9 codes
),
Comorbidities AS (
  -- Calculate comorbidities based on ICD-9 codes
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_comorbidities
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code IN ('401.9', '402.91', '403.91', '404.9', '405.9', '408.1', '408.9', '410.9', '411.1', '412', '413.1', '414.01', '414.03', '414.11', '414.13', '414.21', '414.23', '414.31', '414.33', '414.41', '414.43', '414.51', '414.53', '414.61', '414.63', '414.71', '414.73', '414.81', '414.83', '414.9', '420.9', '421.1', '421.3', '422.9', '423.1', '423.3', '424', '425', '426', '427.31', '427.39', '427.41', '427.49', '427.51', '427.59', '427.6', '427.81', '427.89', '428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.8', '428.9', '429.77', '430.9', '431', '432', '433', '434', '435', '436', '437', '438', '439', '4;