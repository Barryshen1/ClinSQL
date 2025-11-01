WITH admissions_filtered AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        -- Compute hospital LOS in days
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 45 AND 55
      AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
hf_diagnoses AS (
    SELECT 
        d.hadm_id,
        MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) AS has_primary,
        MAX(CASE WHEN d.seq_num > 1 THEN 1 ELSE 0 END) AS has_secondary
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE 
        REGEXP_CONTAINS(LOWER(dd.long_title), r'heart failure| hf ')
        AND d.hadm_id IN (SELECT hadm_id FROM admissions_filtered)
    GROUP BY d.hadm_id
    HAVING MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) = 1 
        OR MAX(CASE WHEN d.seq_num > 1 THEN 1 ELSE 0 END) = 1
),
imaging_counts AS (
    SELECT 
        a.hadm_id,
        COUNT(img.icd_code) AS imaging_count
    FROM admissions_filtered a
    LEFT JOIN (
        SELECT 
            p.hadm_id,
            p.icd_code
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
            ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
        WHERE 
            REGEXP_CONTAINS(LOWER(d.long_title), r'computed tomography|magnetic resonance imaging')
    ) img ON a.hadm_id = img.hadm_id
    GROUP BY a.hadm_id
)
SELECT 
    CASE 
        WHEN hf.has_primary = 1 THEN 'primary'
        WHEN hf.has_secondary = 1 THEN 'secondary'
    END AS diagnosis_type,
    CASE 
        WHEN af.hospital_los BETWEEN 1 AND 3 THEN '1-3'
        WHEN af.hospital_los BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group,
    AVG(ic.imaging_count) AS mean_imaging,
    MIN(ic.imaging_count) AS min_imaging,
    MAX(ic.imaging_count) AS max_imaging
FROM hf_diagnoses hf
INNER JOIN admissions_filtered af ON hf.hadm_id = af.hadm_id
INNER JOIN imaging_counts ic ON af.hadm_id = ic.hadm_id
GROUP BY diagnosis_type, los_group
ORDER BY diagnosis_type, los_group;