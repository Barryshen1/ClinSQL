WITH cohort AS (
    SELECT 
        a.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag,
        p.gender, 
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 89 AND 99
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE 
                d.hadm_id = a.hadm_id
                AND (
                    (d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
                    OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
                )
        )
),
med_complexity AS (
    SELECT 
        c.hadm_id,
        COUNT(DISTINCT p.drug) AS num_drugs
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id
        AND p.starttime >= c.admittime
        AND p.starttime <= c.admittime + INTERVAL '7' DAY
    GROUP BY c.hadm_id
),
readmission AS (
    SELECT 
        a.hadm_id,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE 
                a2.subject_id = a.subject_id
                AND a2.hadm_id != a.hadm_id
                AND a2.admittime >= a.dischtime
                AND a2.admittime <= a.dischtime + INTERVAL '30' DAY
        ) THEN 1 ELSE 0 END AS readmission_30d
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
combined AS (
    SELECT 
        c.hadm_id,
        c.hospital_expire_flag,
        DATE_DIFF(c.dischtime, c.admittime, DAY) AS los,
        mc.num_drugs,
        r.readmission_30d
    FROM cohort c
    LEFT JOIN med_complexity mc ON c.hadm_id = mc.hadm_id
    LEFT JOIN readmission r ON c.hadm_id = r.hadm_id
),
quintiles AS (
    SELECT 
        *,
        NTILE(5) OVER (ORDER BY num_drugs) AS quintile
    FROM combined
)
SELECT 
    quintile,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(readmission_30d) AS readmission_rate
FROM quintiles
GROUP BY quintile
ORDER BY quintile;