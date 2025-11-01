WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        pt.anchor_age,
        pt.gender,
        COUNT(DISTINCT pr.drug) AS num_unique_drugs,
        -- Add high-risk medication classes weighting
        COUNT(DISTINCT CASE 
            WHEN LOWER(pr.drug) LIKE '%warfarin%' OR LOWER(pr.drug) LIKE '%insulin%' 
                 OR LOWER(pr.drug) LIKE '%heparin%' OR LOWER(pr.drug) LIKE '%opioid%'
                 OR LOWER(pr.drug) LIKE '%narcotic%' OR LOWER(pr.drug) LIKE '%chemotherapy%'
            THEN pr.drug 
        END) * 2 AS high_risk_score
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON adm.subject_id = pt.subject_id
    -- Filter for surgical patients using EXISTS to avoid duplicates
    WHERE EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        WHERE adm.hadm_id = proc.hadm_id
    )
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON adm.hadm_id = pr.hadm_id
        AND pr.starttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
    WHERE pt.gender = 'F'
        AND pt.anchor_age BETWEEN 51 AND 61
        AND adm.admission_type = 'ELECTIVE'
    GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag, pt.anchor_age, pt.gender
),
med_complexity AS (
    SELECT 
        *,
        num_unique_drugs + high_risk_score AS complexity_score
    FROM cohort
),
quartiles AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY complexity_score) AS complexity_quartile
    FROM med_complexity
),
readmissions AS (
    SELECT 
        adm1.hadm_id,
        adm1.dischtime,
        CASE 
            WHEN MIN(adm2.admittime) <= DATETIME_ADD(adm1.dischtime, INTERVAL 30 DAY) THEN 1
            ELSE 0 
        END AS readmit_30d
    FROM quartiles adm1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm2
        ON adm1.subject_id = adm2.subject_id
        AND adm2.admittime > adm1.dischtime
        AND adm2.admittime <> adm1.admittime  -- Exclude same admission
    GROUP BY adm1.hadm_id, adm1.dischtime
)
SELECT 
    complexity_quartile,
    COUNT(*) AS n_admissions,
    AVG(DATETIME_DIFF(q.dischtime, q.admittime, DAY)) AS avg_los,
    SUM(hospital_expire_flag) AS in_hospital_deaths,
    AVG(hospital_expire_flag) * 100 AS mortality_percent,
    SUM(readmit_30d) AS readmissions_30d,
    AVG(readmit_30d) * 100 AS readmit_30d_percent
FROM quartiles q
LEFT JOIN readmissions r
    ON q.hadm_id = r.hadm_id
GROUP BY complexity_quartile
ORDER BY complexity_quartile;