WITH
-- First, identify hip fracture ICD codes (both ICD-9 and ICD-10)
hip_fracture_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%hip fracture%'
     OR icd_code IN (
       -- Common ICD-9 codes for hip fracture
       '820.00', '820.01', '820.02', '820.03', '820.09',
       '820.10', '820.11', '820.12', '820.13', '820.19',
       '820.20', '820.21', '820.22', '820.23', '820.29',
       '820.30', '820.31', '820.32', '820.33', '820.39',
       '820.8', '820.9',
       -- Common ICD-10 codes for hip fracture
       'S72.001A', 'S72.001B', 'S72.001C', 'S72.001D', 'S72.001S',
       'S72.002A', 'S72.002B', 'S72.002C', 'S72.002D', 'S72.002S',
       'S72.009A', 'S72.009B', 'S72.009C', 'S72.009D', 'S72.009S',
       'S72.011A', 'S72.011B', 'S72.011C', 'S72.011D', 'S72.011S',
       'S72.012A', 'S72.012B', 'S72.012C', 'S72.012D', 'S72.012S',
       'S72.019A', 'S72.019B', 'S72.019C', 'S72.019D', 'S72.019S',
       'S72.021A', 'S72.021B', 'S72.021C', 'S72.021D', 'S72.021S',
       'S72.022A', 'S72.022B', 'S72.022C', 'S72.022D', 'S72.022S',
       'S72.029A', 'S72.029B', 'S72.029C', 'S72.029D', 'S72.029S',
       'S72.091A', 'S72.091B', 'S72.091C', 'S72.091D', 'S72.091S',
       'S72.092A', 'S72.092B', 'S72.092C', 'S72.092D', 'S72.092S',
       'S72.099A', 'S72.099B', 'S72.099C', 'S72.099D', 'S72.099S'
     )
),

-- Get index admissions (first admission per patient)
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_seq
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Get patients with their age at admission
patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Calculate age at admission (anchor_age is age at first admission)
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN index_admissions a ON p.subject_id = a.subject_id
  WHERE a.admission_seq = 1  -- Only index admissions
),

-- Get admissions with hip fracture as principal diagnosis
hip_fracture_admissions AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.age_at_admission,
    pa.gender,
    a.admission_type,
    a.insurance,
    d.seq_num,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM patient_age pa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON pa.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON pa.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN hip_fracture_codes hfc ON d.icd_code = hfc.icd_code AND d.icd_version = hfc.icd_version
  WHERE d.seq_num = 1  -- Principal diagnosis (first in sequence)
)

-- Final count of patients meeting all criteria
SELECT
  COUNT(DISTINCT hadm_id) AS number_of_index_admissions
FROM hip_fracture_admissions
WHERE
  gender = 'F'
  AND age_at_admission BETWEEN 46 AND 56
  AND admission_type = 'TRANSFER'
  AND insurance = 'Medicare';