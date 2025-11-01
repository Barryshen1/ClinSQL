WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        adm.hospital_expire_flag,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 80 AND 90
        AND adm.hadm_id IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE diag.icd_code LIKE 'K70%'   -- Alcoholic liver disease
                OR diag.icd_code LIKE 'K72%'   -- Hepatic failure
                OR diag.icd_code = 'K76.2'     -- Hepatic necrosis
                OR diag.icd_code = 'K74.6'     -- Cirrhosis (as proxy)
        )
),

meds AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        COUNT(DISTINCT emd.product_description) AS med_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` em
        ON c.hadm_id = em.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` emd
        ON em.emar_id = emd.emar_id
    WHERE em.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
        AND emd.product_description IS NOT NULL
    GROUP BY c.subject_id, c.hadm_id
),

with_med_score AS (
    SELECT 
        c.*,
        COALESCE(m.med_count, 0) AS med_count
    FROM cohort c
    LEFT JOIN meds m
        ON c.hadm_id = m.hadm_id AND c.subject_id = m.subject_id
),

tertiles AS (
    SELECT *,
        NTILE(3) OVER (ORDER BY med_count) AS tertile
    FROM with_med_score
),

readmissions AS (
    SELECT 
        t1.hadm_id AS index_hadm,
        COUNT(t2.hadm_id) AS readmit_30d
    FROM tertiles t1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` t2
        ON t1.subject_id = t2.subject_id
        AND t2.admittime > t1.dischtime
        AND t2.admittime <= DATETIME_ADD(t1.dischtime, INTERVAL 30 DAY)
        AND t1.hospital_expire_flag = 0  -- only if survived index admission
    GROUP BY t1.hadm_id
)

SELECT 
    t.tertile,
    COUNT(*) AS n_admissions,
    AVG(DATETIME_DIFF(t.dischtime, t.admittime, DAY)) AS avg_los,
    AVG(t.hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
    AVG(r.readmit_30d) * 100 AS readmit_30d_percent
FROM tertiles t
LEFT JOIN readmissions r
    ON t.hadm_id = r.index_hadm
WHERE t.dischtime IS NOT NULL   -- exclude ongoing admissions
GROUP BY t.tertile
ORDER BY t.tertile;