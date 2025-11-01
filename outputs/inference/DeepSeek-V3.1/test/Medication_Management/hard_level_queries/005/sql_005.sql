WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Get next admission date for readmission calculation
        LEAD(adm.admittime) OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 43 AND 53
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE adm.subject_id = diag.subject_id
                AND adm.hadm_id = diag.hadm_id
                AND (
                    (diag.icd_version = 10 AND diag.icd_code LIKE 'K72%')
                    OR (diag.icd_version = 9 AND diag.icd_code IN ('570', '572.8', '573.8'))
                )
        )
),

medications AS (
    SELECT 
        cohort.hadm_id,
        COUNT(DISTINCT emar.medication) AS med_count
    FROM cohort
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` emar
        ON cohort.hadm_id = emar.hadm_id
        AND emar.charttime BETWEEN cohort.admittime AND DATETIME_ADD(cohort.admittime, INTERVAL 72 HOUR)
    GROUP BY cohort.hadm_id
),

cohort_with_meds AS (
    SELECT 
        c.*,
        COALESCE(m.med_count, 0) AS med_count,
        -- Calculate 30-day readmission: if next admission within 30 days of discharge
        CASE 
            WHEN c.next_admittime IS NOT NULL 
                AND DATE_DIFF(c.next_admittime, c.dischtime, DAY) <= 30 
            THEN 1 
            ELSE 0 
        END AS readmit_30d
    FROM cohort c
    LEFT JOIN medications m
        ON c.hadm_id = m.hadm_id
),

quintiles AS (
    SELECT 
        *,
        NTILE(5) OVER (ORDER BY med_count) AS quintile
    FROM cohort_with_meds
)

SELECT 
    quintile,
    COUNT(*) AS n,
    MIN(med_count) AS min_score,
    MAX(med_count) AS max_score,
    AVG(med_count) AS mean_score,
    AVG(los_days) AS mean_los,
    AVG(hospital_expire_flag) * 100 AS mortality_percent,
    AVG(readmit_30d) * 100 AS readmit_30d_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;