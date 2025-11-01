WITH cohort AS (
    SELECT 
        adm.hadm_id,
        adm.subject_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 80 AND 90
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
                ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
            WHERE diag.hadm_id = adm.hadm_id
                AND (LOWER(d.long_title) LIKE '%hepatic failure%' 
                     OR LOWER(d.long_title) LIKE '%liver failure%')
        )
),
complexity AS (
    SELECT 
        adm.hadm_id,
        COUNT(DISTINCT LOWER(TRIM(pres.drug))) AS complexity_score
    FROM cohort adm
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
        ON adm.hadm_id = pres.hadm_id
        AND pres.starttime <= adm.admittime + INTERVAL '7' DAY
    GROUP BY adm.hadm_id
),
readmission AS (
    SELECT 
        adm.hadm_id,
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM `physionet-data.mimiciv_3_1_hosp.admissions` next_adm
                WHERE next_adm.subject_id = adm.subject_id
                    AND next_adm.admittime > adm.dischtime
                    AND next_adm.admittime <= adm.dischtime + INTERVAL '30' DAY
            ) THEN 1 
            ELSE 0 
        END AS readmitted_30d
    FROM cohort adm
),
main AS (
    SELECT 
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag,
        TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / (24*60*60.0) AS los_days,
        comp.complexity_score,
        read.readmitted_30d
    FROM cohort c
    LEFT JOIN complexity comp ON c.hadm_id = comp.hadm_id
    LEFT JOIN readmission read ON c.hadm_id = read.hadm_id
),
with_tertile AS (
    SELECT 
        *,
        NTILE(3) OVER (ORDER BY complexity_score) AS tertile
    FROM main
)
SELECT 
    tertile,
    AVG(los_days) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(readmitted_30d) AS readmission_rate
FROM with_tertile
GROUP BY tertile
ORDER BY tertile;