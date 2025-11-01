WITH admissions_filtered AS (
     SELECT 
       hadm_id,
       subject_id,
       admittime,
       dischtime,
       hospital_expire_flag,
       DATEDIFF(dischtime, admittime) AS los_days
     FROM `physionet-data.mimiciv_3_1_hosp.admissions`
     WHERE admittime BETWEEN '2013-01-01' AND '2023-12-31'
       AND dischtime IS NOT NULL
   ),
   cohort AS (
     SELECT
       af.hadm_id,
       af.subject_id,
       af.hospital_expire_flag,
       af.los_days,
       MAX(CASE WHEN d_ckd.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_ckd,
       MAX(CASE WHEN d_diabetes.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_diabetes
     FROM admissions_filtered af
     INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
       ON af.subject_id = p.subject_id
       AND p.gender = 'F'
       AND p.anchor_age BETWEEN 62 AND 72
     -- Left join for CKD diagnoses
     LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_ckd
       ON af.hadm_id = d_ckd.hadm_id
       AND d_ckd.icd_version = 10
       AND (d_ckd.icd_code LIKE 'N18.1%' OR d_ckd.icd_code LIKE 'N18.3%' OR 
            d_ckd.icd_code LIKE 'N18.5%' OR d_ckd.icd_code LIKE 'N18.6%' OR 
            d_ckd.icd_code LIKE 'N18.9%')
     -- Left join for diabetes diagnoses
     LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_diabetes
       ON af.hadm_id = d_diabetes.hadm_id
       AND d_diabetes.icd_version = 10
       AND (d_diabetes.icd_code LIKE 'E10%' OR d_diabetes.icd_code LIKE 'E11%')
     -- Now apply the WHERE conditions after the JOINs
     WHERE 
       -- AMI condition: at least one AMI diagnosis
       EXISTS (
         SELECT 1
         FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
         WHERE d.hadm_id = af.hadm_id
           AND d.icd_version = 10
           AND d.icd_code LIKE 'I21.%'
       )
       -- Exclude shock
       AND NOT EXISTS (
         SELECT 1
         FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
         WHERE d.hadm_id = af.hadm_id
           AND d.icd_version = 10
           AND d.icd_code LIKE 'R57%'
       )
       -- Exclude respiratory failure
       AND NOT EXISTS (
         SELECT 1
         FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
         WHERE d.hadm_id = af.hadm_id
           AND d.icd_version = 10
           AND (d.icd_code LIKE 'J95.8%' OR d.icd_code LIKE 'J95.9%')
       )
     GROUP BY af.hadm_id, af.subject_id, af.hospital_expire_flag, af.los_days
   );