WITH ami_admissions AS (
    SELECT d.subject_id, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE (d.icd_version = 9 AND d.icd_code LIKE '410%')
        OR (d.icd_version = 10 AND d.icd_code LIKE 'I21.%')
),
eligible_patients AS (
    SELECT subject_id, anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
        AND anchor_age BETWEEN 76 AND 86
),
ami_icustays AS (
    SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN eligible_patients e ON i.subject_id = e.subject_id
    INNER JOIN ami_admissions a ON i.hadm_id = a.hadm_id
),
procedure_counts AS (
    SELECT 
        a.hadm_id, 
        a.stay_id, 
        a.los,
        COUNT(DISTINCT p.itemid) AS distinct_procedure_count
    FROM ami_icustays a
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
        ON a.subject_id = p.subject_id 
        AND a.hadm_id = p.hadm_id 
        AND a.stay_id = p.stay_id
        AND p.starttime >= a.intime 
        AND p.starttime < a.intime + INTERVAL 24 HOUR
    GROUP BY a.hadm_id, a.stay_id, a.los
),
quartiles AS (
    SELECT 
        hadm_id, 
        stay_id, 
        distinct_procedure_count, 
        los,
        NTILE(4) OVER (ORDER BY distinct_procedure_count) AS quartile
    FROM procedure_counts
),
icustays_with_mortality AS (
    SELECT 
        q.quartile,
        q.distinct_procedure_count,
        q.los,
        a.hospital_expire_flag
    FROM quartiles q
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON q.hadm_id = a.hadm_id
)
SELECT 
    quartile,
    AVG(distinct_procedure_count) AS mean_procedure_count,
    AVG(los) AS mean_icu_los,
    (AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) * 100) AS hospital_mortality_percent
FROM icustays_with_mortality
GROUP BY quartile
ORDER BY quartile;