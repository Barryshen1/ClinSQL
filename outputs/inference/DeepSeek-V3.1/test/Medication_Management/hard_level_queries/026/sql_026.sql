WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 76 AND 86
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE adm.hadm_id = diag.hadm_id
                AND (
                    (diag.icd_version = 10 AND diag.icd_code LIKE 'J18%') 
                    OR (diag.icd_version = 9 AND diag.icd_code = '486')
                )
        )
),

med_complexity AS (
    SELECT 
        c.hadm_id,
        COUNT(DISTINCT pr.drug) AS num_drugs
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON c.hadm_id = pr.hadm_id
        AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    GROUP BY c.hadm_id
),

tertiles AS (
    SELECT 
        mc.hadm_id,
        mc.num_drugs,
        NTILE(3) OVER (ORDER BY mc.num_drugs) AS tertile
    FROM med_complexity mc
),

readmissions AS (
    SELECT 
        c1.hadm_id,
        MIN(c2.admittime) AS readmit_time
    FROM cohort c1
    LEFT JOIN cohort c2
        ON c1.subject_id = c2.subject_id
        AND c2.admittime > c1.dischtime
        AND c2.admittime <= DATETIME_ADD(c1.dischtime, INTERVAL 30 DAY)
    GROUP BY c1.hadm_id
)

SELECT 
    t.tertile,
    COUNT(*) AS admission_count,
    MIN(t.num_drugs) AS min_drugs,
    ROUND(AVG(t.num_drugs), 2) AS avg_drugs,
    MAX(t.num_drugs) AS max_drugs,
    ROUND(AVG(DATETIME_DIFF(c.dischtime, c.admittime, DAY)), 2) AS mean_los,
    ROUND(100.0 * SUM(c.hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    ROUND(100.0 * SUM(CASE WHEN ra.readmit_time IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS readmission_30_percent
FROM tertiles t
INNER JOIN cohort c
    ON t.hadm_id = c.hadm_id
LEFT JOIN readmissions ra
    ON t.hadm_id = ra.hadm_id
GROUP BY t.tertile
ORDER BY t.tertile;