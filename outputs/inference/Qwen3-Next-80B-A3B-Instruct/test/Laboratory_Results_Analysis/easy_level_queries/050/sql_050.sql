WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime, p.gender
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND LOWER(d_icd.long_title) LIKE '%sepsis%'
),

platelet_labs AS (
  SELECT l.hadm_id, l.valuenum, l.charttime
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems d ON l.itemid = d.itemid
  WHERE LOWER(d.label) IN ('platelets', 'plt', 'platelet count')
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0  -- exclude implausible values (e.g., negative or zero)
),

admission_platelet AS (
  SELECT s.hadm_id, 
         FIRST_VALUE(p.valuenum) OVER (
           PARTITION BY s.hadm_id 
           ORDER BY ABS(TIMESTAMP_DIFF(p.charttime, s.admittime, MINUTE))
         ) AS admission_platelet_val
  FROM sepsis_admissions s
  JOIN platelet_labs p ON s.hadm_id = p.hadm_id
  WHERE p.charttime BETWEEN TIMESTAMP_SUB(s.admittime, INTERVAL 24 HOUR) 
                        AND TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR)
)

SELECT STDDEV(admission_platelet_val) AS admission_platelet_count_stddev
FROM admission_platelet
WHERE admission_platelet_val IS NOT NULL;