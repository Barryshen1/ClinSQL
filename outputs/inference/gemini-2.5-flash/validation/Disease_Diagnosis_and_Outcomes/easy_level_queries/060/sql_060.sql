WITH hemorrhage_admissions AS (
        SELECT DISTINCT di.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        WHERE di.seq_num = 1 -- Only primary diagnosis
        AND (
            -- ICD-9 codes for Upper GI Bleed
            (di.icd_version = 9 AND (
                   di.icd_code LIKE '5312%' OR -- Acute gastric ulcer with perforation and hemorrhage
                   di.icd_code LIKE '5314%' OR -- Chronic gastric ulcer with hemorrhage
                   di.icd_code LIKE '5316%' OR -- Chronic gastric ulcer with perforation and hemorrhage
                   di.icd_code LIKE '5320%' OR -- Acute duodenal ulcer with hemorrhage
                   di.icd_code LIKE '5322%' OR -- Acute duodenal ulcer with perforation and hemorrhage
                   di.icd_code LIKE '5324%' OR -- Chronic duodenal ulcer with hemorrhage
                   di.icd_code LIKE '5326%' OR -- Chronic duodenal ulcer with perforation and hemorrhage
                   di.icd_code LIKE '5330%' OR -- Acute peptic ulcer, site unspecified, with hemorrhage
                   di.icd_code LIKE '5332%' OR -- Acute peptic ulcer, site unspecified, with perforation and hemorrhage
                   di.icd_code LIKE '5334%' OR -- Chronic peptic ulcer, site unspecified, with hemorrhage
                   di.icd_code LIKE '5336%' OR -- Chronic peptic ulcer, site unspecified, with perforation and hemorrhage
                   di.icd_code LIKE '5340%' OR -- Acute gastrojejunal ulcer with hemorrhage
                   di.icd_code LIKE '5342%' OR -- Acute gastrojejunal ulcer with perforation and hemorrhage
                   di.icd_code LIKE '5344%' OR -- Chronic gastrojejunal ulcer with hemorrhage
                   di.icd_code LIKE '5346%' OR -- Chronic gastrojejunal ulcer with perforation and hemorrhage
                   di.icd_code IN ('4560', '45620') OR -- Esophageal varices with bleeding
                   di.icd_code IN ('5780', '5781', '5789') -- Hematemesis, Melena, GI hemorrhage unspecified
            ))
            OR
            -- ICD-10 codes for Upper GI Bleed
            (di.icd_version = 10 AND (
                   di.icd_code LIKE 'K250%' OR -- Acute gastric ulcer with hemorrhage
                   di.icd_code LIKE 'K252%' OR -- Acute gastric ulcer with perforation and hemorrhage
                   di.icd_code LIKE 'K254%' OR -- Chronic gastric ulcer with hemorrhage
                   di.icd_code LIKE 'K256%' OR -- Chronic gastric ulcer with perforation and hemorrhage
                   di.icd_code LIKE 'K260%' OR -- Acute duodenal ulcer with hemorrhage
                   di.icd_code LIKE 'K262%' OR -- Acute duodenal ulcer with perforation and hemorrhage
                   di.icd_code LIKE 'K264%' OR -- Chronic duodenal ulcer with hemorrhage
                   di.icd_code LIKE 'K266%' OR -- Chronic duodenal ulcer with perforation and hemorrhage
                   di.icd_code LIKE 'K270%' OR -- Acute peptic ulcer, site unspecified, with hemorrhage
                   di.icd_code LIKE 'K272%' OR -- Acute peptic ulcer, site unspecified, with perforation and hemorrhage
                   di.icd_code LIKE 'K274%' OR -- Chronic peptic ulcer, site unspecified, with hemorrhage
                   di.icd_code LIKE 'K276%' OR -- Chronic peptic ulcer, site unspecified, with perforation and hemorrhage
                   di.icd_code LIKE 'K280%' OR -- Acute gastrojejunal ulcer with hemorrhage
                   di.icd_code LIKE 'K282%' OR -- Acute gastrojejunal ulcer with perforation and hemorrhage
                   di.icd_code LIKE 'K284%' OR -- Chronic gastrojejunal ulcer with hemorrhage
                   di.icd_code LIKE 'K286%' OR -- Chronic gastrojejunal ulcer with perforation and hemorrhage
                   di.icd_code IN ('I8501') OR -- Esophageal varices with bleeding
                   di.icd_code IN ('K920', 'K921', 'K922') -- Hematemesis, Melena, GI hemorrhage unspecified
            ))
        )
    ),
    filtered_los AS (
        SELECT
            DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS LOS_days
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pa
            ON ad.subject_id = pa.subject_id
        INNER JOIN hemorrhage_admissions AS ha
            ON ad.hadm_id = ha.hadm_id
        WHERE
            pa.gender = 'M'
            AND pa.anchor_age BETWEEN 74 AND 84
    )
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY LOS_days) OVER () AS LOS_25th_percentile_days
    FROM filtered_los
    LIMIT 1;