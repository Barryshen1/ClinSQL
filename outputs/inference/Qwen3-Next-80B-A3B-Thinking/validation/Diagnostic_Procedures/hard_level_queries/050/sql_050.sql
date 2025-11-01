WITH amipatients AS (
    SELECT DISTINCT a.hadm_id, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 76 AND 86
        AND d_icd.long_title LIKE '%myocardial infarction%'
),

icu_stays AS (
    SELECT i.stay_id, i.hadm_id, i.intime, i.outtime, i.los,
           a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN amipatients a ON i.hadm_id = a.hadm_id
),

proc_counts AS (
    SELECT p.stay_id,
           COUNT(DISTINCT p.itemid) AS procedure_count
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
    JOIN icu_stays i ON p.stay_id = i.stay_id
    WHERE p.starttime >= i.intime
        AND p.starttime <= i.intime + INTERVAL '24' HOUR
    GROUP BY p.stay_id
)

SELECT quartile,
       AVG(procedure_count) AS mean_procedure_count,
       AVG(los) AS mean_los,
       (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS hospital_mortality_pct
FROM (
    SELECT i.stay_id,
           i.los,
           i.hospital_expire_flag,
           COALESCE(pc.procedure_count, 0) AS procedure_count,
           NTILE(4) OVER (ORDER BY COALESCE(pc.procedure_count, 0)) AS quartile
    FROM icu_stays i
    LEFT JOIN proc_counts pc ON i.stay_id = pc.stay_id
) AS stratified
GROUP BY quartile
ORDER BY quartile;