WITH first_pci_admission AS (
    SELECT 
        a.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime,
        pt.gender,
        pt.anchor_age,
        pt.anchor_year,
        ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt 
        ON a.subject_id = pt.subject_id
    WHERE (d.long_title LIKE '%PCI%' OR d.long_title LIKE '%coronary angioplasty%')
        AND pt.gender = 'M'
        AND (pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year)) BETWEEN 52 AND 62
),
readmissions AS (
    SELECT 
        f.subject_id,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE a2.subject_id = f.subject_id
                AND a2.hadm_id != f.hadm_id
                AND a2.admittime >= f.dischtime
                AND a2.admittime <= DATE_ADD(f.dischtime, INTERVAL 30 DAY)
        ) THEN 1 ELSE 0 END AS readmitted
    FROM first_pci_admission f
    WHERE f.rn = 1
)
SELECT AVG(readmitted) AS avg_readmission_rate
FROM readmissions;