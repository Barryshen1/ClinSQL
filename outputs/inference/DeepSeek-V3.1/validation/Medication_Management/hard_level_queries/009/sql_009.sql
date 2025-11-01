WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN (
        SELECT hadm_id 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
            ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
        WHERE d.long_title LIKE 'Acute kidney injury%'
    ) aki ON adm.hadm_id = aki.hadm_id
    WHERE pat.gender = 'F' 
        AND pat.anchor_age BETWEEN 84 AND 94
),

med_count AS (
    SELECT 
        hadm_id,
        COUNT(DISTINCT drug) AS num_drugs
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    GROUP BY hadm_id
),

quintiles AS (
    SELECT 
        c.*,
        mc.num_drugs,
        NTILE(5) OVER (ORDER BY mc.num_drugs) AS quintile
    FROM cohort c
    LEFT JOIN med_count mc
        ON c.hadm_id = mc.hadm_id
),

readmissions AS (
    SELECT 
        q1.hadm_id,
        q1.dischtime,  -- Include dischtime for the DATE_DIFF calculation
        CASE WHEN MIN(q2.admittime) IS NOT NULL AND 
                  DATE_DIFF(MIN(q2.admittime), q1.dischtime, DAY) BETWEEN 1 AND 30 
             THEN 1 ELSE 0 
        END AS readmit_30d
    FROM quintiles q1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` q2
        ON q1.subject_id = q2.subject_id
        AND q2.admittime > q1.dischtime
    GROUP BY q1.hadm_id, q1.dischtime  -- Group by dischtime as well
),

anticoag_opioid_days AS (
    WITH med_calendar AS (
        SELECT 
            pr.hadm_id,
            DATE(pr.starttime) AS drug_date,
            MAX(CASE WHEN pr.drug LIKE '%warfarin%' OR pr.drug LIKE '%heparin%' OR pr.drug LIKE '%enoxaparin%' 
                          OR pr.drug LIKE '%apixaban%' OR pr.drug LIKE '%rivaroxaban%' OR pr.drug LIKE '%dabigatran%' 
                     THEN 1 ELSE 0 END) AS anticoag,
            MAX(CASE WHEN pr.drug LIKE '%morphine%' OR pr.drug LIKE '%fentanyl%' OR pr.drug LIKE '%oxycodone%' 
                          OR pr.drug LIKE '%hydromorphone%' OR pr.drug LIKE '%codeine%' 
                     THEN 1 ELSE 0 END) AS opioid
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        INNER JOIN quintiles q
            ON pr.hadm_id = q.hadm_id
        WHERE pr.starttime IS NOT NULL
        GROUP BY pr.hadm_id, DATE(pr.starttime)
    )
    SELECT 
        hadm_id,
        COUNT(DISTINCT drug_date) AS coadmin_days
    FROM med_calendar
    WHERE anticoag = 1 AND opioid = 1
    GROUP BY hadm_id
)

SELECT 
    quintile,
    COUNT(*) AS num_admissions,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) * 100 AS mortality_pct,
    AVG(readmit_30d) * 100 AS readmit_30d_pct,
    SUM(COALESCE(aod.coadmin_days, 0)) AS anticoag_opioid_coadmin_days
FROM quintiles q
LEFT JOIN readmissions r
    ON q.hadm_id = r.hadm_id
LEFT JOIN anticoag_opioid_days aod
    ON q.hadm_id = aod.hadm_id
GROUP BY quintile
ORDER BY quintile;