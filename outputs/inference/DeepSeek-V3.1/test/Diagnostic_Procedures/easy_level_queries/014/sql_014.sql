WITH device_codes AS (
  -- Common ICD-10 codes for mechanical circulatory support devices
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    (icd_code LIKE '5A021%' OR  -- IABP
     icd_code LIKE '5A022%' OR  -- Other counterpulsation
     icd_code LIKE '5A152%' OR  -- ECMO
     icd_code LIKE '5A1D%'  OR  -- Other extracorporeal assistance
     icd_code LIKE '02HA%'  OR  -- VAD implantation
     icd_code LIKE '5A122%')    -- Other assist
    AND icd_version = 10
),

admissions_with_devices AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    proc.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS num_devices
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  INNER JOIN device_codes dc
    ON proc.icd_code = dc.icd_code AND proc.icd_version = dc.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
  GROUP BY p.subject_id, p.gender, p.anchor_age, proc.hadm_id
)

SELECT 
  APPROX_QUANTILES(num_devices, 100)[OFFSET(50)] AS median_devices_per_hospitalization
FROM admissions_with_devices;